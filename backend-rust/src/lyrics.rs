use std::{
    collections::HashSet,
    num::NonZeroUsize,
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

use lru::LruCache;
use reqwest::Client;
use serde::Deserialize;
use tokio::sync::Mutex;
use url::Url;

use crate::model::{PlayerState, Track};

const YESPLAYMUSIC_BUS: &str = "org.mpris.MediaPlayer2.yesplaymusic";

pub fn is_open_orpheus(player: &PlayerState) -> bool {
    player.identity == "Open Orpheus"
        || matches!(
            player.bus_name.as_str(),
            "org.mpris.MediaPlayer2.open-orpheus"
                | "org.mpris.MediaPlayer2.io.github.yucling.open-orpheus"
        )
}

fn open_orpheus_song_id(track: &Track) -> Option<&str> {
    let id = track.track_id.strip_prefix("/com/163/music/")?;
    (!id.is_empty()
        && id.bytes().all(|byte| byte.is_ascii_digit())
        && id.bytes().any(|byte| byte != b'0'))
    .then_some(id)
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
struct LyricsKey {
    global_mode: bool,
    bus_name: String,
    track_id: String,
    title: String,
    artists: Vec<String>,
    album: String,
    duration_us: i64,
    url: String,
}

impl LyricsKey {
    fn new(player: &PlayerState, global_mode: bool) -> Self {
        Self {
            global_mode,
            bus_name: player.bus_name.clone(),
            track_id: player.track.track_id.clone(),
            title: player.track.title.clone(),
            artists: player.track.artists.clone(),
            album: player.track.album.clone(),
            duration_us: player.track.duration_us,
            url: player.track.url.clone(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LyricLine {
    pub time_us: i64,
    pub lyric: String,
}

pub struct LyricsManager {
    client: Client,
    cache: Mutex<LruCache<LyricsKey, CacheEntry>>,
    pending: Mutex<HashSet<LyricsKey>>,
}

#[derive(Clone)]
struct CacheEntry {
    lyrics: Option<Arc<Vec<LyricLine>>>,
    stored_at: Instant,
}

impl LyricsManager {
    pub fn new() -> Result<Arc<Self>, reqwest::Error> {
        Ok(Arc::new(Self {
            client: Client::builder()
                .timeout(Duration::from_secs(5))
                .user_agent("lyrics-on-panel/0.1")
                .build()?,
            cache: Mutex::new(LruCache::new(
                NonZeroUsize::new(128).expect("nonzero cache size"),
            )),
            pending: Mutex::new(HashSet::new()),
        }))
    }

    pub async fn get_or_schedule(
        self: &Arc<Self>,
        player: &PlayerState,
        global_mode: bool,
    ) -> Option<Arc<Vec<LyricLine>>> {
        let key = LyricsKey::new(player, global_mode);
        let mut cache = self.cache.lock().await;
        if let Some(cached) = cache.get(&key).cloned() {
            if cached.lyrics.is_some() || cached.stored_at.elapsed() < Duration::from_secs(30) {
                return cached.lyrics;
            }
            cache.pop(&key);
        }
        drop(cache);
        if (global_mode || !is_open_orpheus(player))
            && (player.track.title.is_empty() || player.track.artists.is_empty())
        {
            self.cache.lock().await.put(
                key,
                CacheEntry {
                    lyrics: None,
                    stored_at: Instant::now(),
                },
            );
            return None;
        }
        let mut pending = self.pending.lock().await;
        if pending.insert(key.clone()) {
            let manager = Arc::clone(self);
            let player = player.clone();
            tokio::spawn(async move {
                let lyrics = manager.fetch(&player, global_mode).await.map(Arc::new);
                manager.cache.lock().await.put(
                    key.clone(),
                    CacheEntry {
                        lyrics,
                        stored_at: Instant::now(),
                    },
                );
                manager.pending.lock().await.remove(&key);
            });
        }
        None
    }

    async fn fetch(&self, player: &PlayerState, global_mode: bool) -> Option<Vec<LyricLine>> {
        if global_mode {
            return self.fetch_lrclib(&player.track).await;
        }
        if is_open_orpheus(player) {
            return self.fetch_open_orpheus(&player.track).await;
        }
        if player.bus_name == YESPLAYMUSIC_BUS {
            return self.fetch_yesplaymusic(&player.track).await;
        }
        if let Some(lyrics) = fetch_local(&player.track).await {
            return Some(lyrics);
        }
        self.fetch_lrclib(&player.track).await
    }

    async fn fetch_open_orpheus(&self, track: &Track) -> Option<Vec<LyricLine>> {
        self.fetch_netease(track, "https://music.163.com/api/song/lyric")
            .await
    }

    async fn fetch_netease(&self, track: &Track, endpoint: &str) -> Option<Vec<LyricLine>> {
        let id = open_orpheus_song_id(track)?;
        let response: NeteaseLyrics = self
            .client
            .get(endpoint)
            .query(&[
                ("id", id),
                ("os", "pc"),
                ("lv", "-1"),
                ("kv", "-1"),
                ("tv", "-1"),
                ("yv", "-1"),
                ("rv", "-1"),
            ])
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json()
            .await
            .ok()?;
        response.parse()
    }

    async fn fetch_yesplaymusic(&self, track: &Track) -> Option<Vec<LyricLine>> {
        let player: YesPlayMusicPlayer = self
            .client
            .get("http://localhost:27232/player")
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json()
            .await
            .ok()?;
        let current = player.current_track?;
        if current.name != track.title {
            return None;
        }
        let lyric: YesPlayMusicLyrics = self
            .client
            .get("http://localhost:27232/api/lyric")
            .query(&[("id", current.id)])
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json()
            .await
            .ok()?;
        parse_lrc(&lyric.lrc?.lyric)
    }

    async fn fetch_lrclib(&self, track: &Track) -> Option<Vec<LyricLine>> {
        let artist = track.artists.first()?.as_str();
        let exact = self.fetch_lrclib_exact(track, artist);
        let search = self.fetch_lrclib_search(track, artist);
        let fuzzy = self.fetch_lrclib_fuzzy(&track.title);
        let (exact, search, fuzzy) = tokio::join!(exact, search, fuzzy);
        exact.or(search).or(fuzzy).and_then(|text| parse_lrc(&text))
    }

    async fn fetch_lrclib_exact(&self, track: &Track, artist: &str) -> Option<String> {
        if track.duration_us <= 0 {
            return None;
        }
        self.client
            .get("https://lrclib.net/api/get")
            .query(&[
                ("track_name", track.title.as_str()),
                ("artist_name", artist),
                ("album_name", track.album.as_str()),
                ("duration", &(track.duration_us / 1_000_000).to_string()),
            ])
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json::<LrcLibEntry>()
            .await
            .ok()?
            .synced_lyrics
    }

    async fn fetch_lrclib_search(&self, track: &Track, artist: &str) -> Option<String> {
        self.client
            .get("https://lrclib.net/api/search")
            .query(&[
                ("track_name", track.title.as_str()),
                ("artist_name", artist),
                ("album_name", track.album.as_str()),
            ])
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json::<Vec<LrcLibEntry>>()
            .await
            .ok()?
            .into_iter()
            .find_map(|entry| entry.synced_lyrics)
    }

    async fn fetch_lrclib_fuzzy(&self, title: &str) -> Option<String> {
        self.client
            .get("https://lrclib.net/api/search")
            .query(&[("q", title)])
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json::<Vec<LrcLibEntry>>()
            .await
            .ok()?
            .into_iter()
            .find_map(|entry| entry.synced_lyrics)
    }
}

async fn fetch_local(track: &Track) -> Option<Vec<LyricLine>> {
    let url = Url::parse(&track.url).ok()?;
    if url.scheme() != "file" {
        return None;
    }
    let mut path: PathBuf = url.to_file_path().ok()?;
    path.set_extension("lrc");
    let text = tokio::fs::read_to_string(path).await.ok()?;
    parse_lrc(&text)
}

pub fn current_lyric(lyrics: &[LyricLine], position_us: i64) -> Option<String> {
    let index = lyrics.partition_point(|line| line.time_us <= position_us);
    lyrics[..index]
        .iter()
        .rev()
        .find(|line| !line.lyric.is_empty())
        .map(|line| line.lyric.clone())
}

pub fn parse_lrc(text: &str) -> Option<Vec<LyricLine>> {
    let mut lines = Vec::new();
    for raw_line in text.lines() {
        let mut rest = raw_line.trim();
        let mut timestamps = Vec::new();
        while let Some(tag) = rest
            .strip_prefix('[')
            .and_then(|value| value.split_once(']'))
        {
            if let Some(time_us) = parse_timestamp(tag.0) {
                timestamps.push(time_us);
            }
            rest = tag.1;
        }
        let lyric = rest.trim().to_owned();
        lines.extend(timestamps.into_iter().map(|time_us| LyricLine {
            time_us,
            lyric: lyric.clone(),
        }));
    }
    lines.sort_by_key(|line| line.time_us);
    (!lines.is_empty()).then_some(lines)
}

fn parse_timestamp(value: &str) -> Option<i64> {
    let (minutes, seconds) = value.split_once(':')?;
    let minutes: i64 = minutes.parse().ok()?;
    let seconds: f64 = seconds.parse().ok()?;
    if minutes < 0 || !seconds.is_finite() || !(0.0..60.0).contains(&seconds) {
        return None;
    }
    Some(((minutes as f64 * 60.0 + seconds) * 1_000_000.0) as i64)
}

#[derive(Deserialize)]
struct YesPlayMusicPlayer {
    #[serde(rename = "currentTrack")]
    current_track: Option<YesPlayMusicTrack>,
}

#[derive(Deserialize)]
struct YesPlayMusicTrack {
    id: serde_json::Value,
    name: String,
}

#[derive(Deserialize)]
struct YesPlayMusicLyrics {
    lrc: Option<YesPlayMusicLrc>,
}

#[derive(Deserialize)]
struct YesPlayMusicLrc {
    lyric: String,
}

#[derive(Deserialize)]
struct NeteaseLyrics {
    code: i64,
    lrc: Option<YesPlayMusicLrc>,
}

impl NeteaseLyrics {
    fn parse(self) -> Option<Vec<LyricLine>> {
        if self.code != 200 {
            return None;
        }
        parse_lrc(&self.lrc?.lyric)
    }
}

#[derive(Deserialize)]
struct LrcLibEntry {
    #[serde(rename = "syncedLyrics")]
    synced_lyrics: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::{
        current_lyric, open_orpheus_song_id, parse_lrc, LyricLine, LyricsKey, LyricsManager,
        NeteaseLyrics,
    };
    use crate::model::{PlaybackStatus, PlayerState, Track};
    use std::time::Instant;

    #[test]
    fn open_orpheus_ids_are_only_positive_netease_track_paths() {
        for id in ["2111993059", "9007199254740993"] {
            let track = Track {
                track_id: format!("/com/163/music/{id}"),
                ..Track::default()
            };
            assert_eq!(open_orpheus_song_id(&track), Some(id));
        }
        for path in [
            "",
            "/org/mpris/MediaPlayer2/Track/2111993059",
            "/com/163/music/0",
            "/com/163/music/000",
            "/com/163/music/-1",
            "/com/163/music/local_song",
            "/com/163/music/123/456",
            "/com/163/music/123?other=1",
        ] {
            let track = Track {
                track_id: path.into(),
                ..Track::default()
            };
            assert_eq!(open_orpheus_song_id(&track), None, "{path}");
        }
    }

    #[test]
    fn same_title_with_different_song_id_has_separate_cache_entry() {
        let mut player = PlayerState {
            bus_name: "org.mpris.MediaPlayer2.open-orpheus".into(),
            identity: "Open Orpheus".into(),
            track: Track {
                track_id: "/com/163/music/1".into(),
                ..Track::default()
            },
            playback_status: PlaybackStatus::Playing,
            rate: 1.0,
            base_position_us: 0,
            position_updated_at: Instant::now(),
        };
        let first = LyricsKey::new(&player, false);
        assert_ne!(first, LyricsKey::new(&player, true));
        player.track.track_id = "/com/163/music/2".into();
        assert_ne!(first, LyricsKey::new(&player, false));
    }

    #[tokio::test]
    async fn global_mode_cannot_reuse_netease_cache_or_fetch_by_id_only() {
        let manager = LyricsManager::new().unwrap();
        let player = PlayerState {
            bus_name: "org.mpris.MediaPlayer2.open-orpheus".into(),
            identity: "Open Orpheus".into(),
            track: Track {
                track_id: "/com/163/music/2111993059".into(),
                ..Track::default()
            },
            playback_status: PlaybackStatus::Playing,
            rate: 1.0,
            base_position_us: 0,
            position_updated_at: Instant::now(),
        };
        manager.cache.lock().await.put(
            LyricsKey::new(&player, false),
            super::CacheEntry {
                lyrics: Some(std::sync::Arc::new(vec![LyricLine {
                    time_us: 0,
                    lyric: "NetEase".into(),
                }])),
                stored_at: Instant::now(),
            },
        );
        assert!(manager.get_or_schedule(&player, false).await.is_some());
        assert!(manager.get_or_schedule(&player, true).await.is_none());
        assert!(manager.pending.lock().await.is_empty());
        assert!(manager.get_or_schedule(&player, false).await.is_some());
    }

    #[test]
    fn netease_error_and_instrumental_responses_have_no_lyrics() {
        for body in [
            r#"{"code":200,"nolyric":true}"#,
            r#"{"code":200,"lrc":{"lyric":""}}"#,
            r#"{"code":404,"lrc":{"lyric":"[00:01]ignored"}}"#,
        ] {
            assert!(serde_json::from_str::<NeteaseLyrics>(body)
                .unwrap()
                .parse()
                .is_none());
        }
    }

    #[tokio::test]
    async fn netease_http_request_uses_id_and_all_version_parameters() {
        use axum::{extract::Query, routing::get, Json, Router};
        use std::collections::HashMap;
        let app = Router::new().route(
            "/api/song/lyric",
            get(|Query(query): Query<HashMap<String, String>>| async move {
                assert_eq!(query.len(), 7);
                assert_eq!(query["id"], "2111993059");
                assert_eq!(query["os"], "pc");
                for version in ["lv", "kv", "tv", "yv", "rv"] {
                    assert_eq!(query[version], "-1");
                }
                Json(serde_json::json!({"code":200,"lrc":{"lyric":"[00:01]first\n[00:02]second"}}))
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}/api/song/lyric", listener.local_addr().unwrap());
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let manager = LyricsManager::new().unwrap();
        let track = Track {
            track_id: "/com/163/music/2111993059".into(),
            ..Track::default()
        };
        let lyrics = manager.fetch_netease(&track, &endpoint).await.unwrap();
        assert_eq!(current_lyric(&lyrics, 1_500_000).as_deref(), Some("first"));
        assert_eq!(current_lyric(&lyrics, 2_000_000).as_deref(), Some("second"));
        server.abort();
    }

    #[test]
    fn parses_fractional_and_repeated_timestamps_in_microseconds() {
        let parsed = parse_lrc("[ar:Artist]\n[00:01.50][00:03.125] hello \n[01:02]world").unwrap();
        assert_eq!(
            parsed,
            vec![
                LyricLine {
                    time_us: 1_500_000,
                    lyric: "hello".into()
                },
                LyricLine {
                    time_us: 3_125_000,
                    lyric: "hello".into()
                },
                LyricLine {
                    time_us: 62_000_000,
                    lyric: "world".into()
                },
            ]
        );
    }

    #[test]
    fn ignores_invalid_lines_and_sorts_timestamps() {
        let parsed = parse_lrc("plain\n[00:05]later\n[bad]ignored\n[00:01]first").unwrap();
        assert_eq!(parsed[0].lyric, "first");
        assert_eq!(parsed[1].lyric, "later");
    }

    #[test]
    fn current_lyric_uses_previous_nonempty_line() {
        let lyrics = parse_lrc("[00:01]one\n[00:02]\n[00:03]three").unwrap();
        assert_eq!(current_lyric(&lyrics, 500_000), None);
        assert_eq!(current_lyric(&lyrics, 2_500_000).as_deref(), Some("one"));
        assert_eq!(current_lyric(&lyrics, 3_000_000).as_deref(), Some("three"));
    }
}
