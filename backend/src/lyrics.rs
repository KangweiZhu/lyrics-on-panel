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

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
struct LyricsKey {
    bus_name: String,
    track_id: String,
    title: String,
    artists: Vec<String>,
    album: String,
    duration_us: i64,
    url: String,
}

impl LyricsKey {
    fn new(player: &PlayerState) -> Self {
        Self {
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
    ) -> Option<Arc<Vec<LyricLine>>> {
        let key = LyricsKey::new(player);
        let mut cache = self.cache.lock().await;
        if let Some(cached) = cache.get(&key).cloned() {
            if cached.lyrics.is_some() || cached.stored_at.elapsed() < Duration::from_secs(30) {
                return cached.lyrics;
            }
            cache.pop(&key);
        }
        drop(cache);
        if player.track.title.is_empty() || player.track.artists.is_empty() {
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
                let lyrics = manager.fetch(&player).await.map(Arc::new);
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

    async fn fetch(&self, player: &PlayerState) -> Option<Vec<LyricLine>> {
        if player.bus_name == YESPLAYMUSIC_BUS {
            return self.fetch_yesplaymusic(&player.track).await;
        }
        if let Some(lyrics) = fetch_local(&player.track).await {
            return Some(lyrics);
        }
        self.fetch_lrclib(&player.track).await
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
struct LrcLibEntry {
    #[serde(rename = "syncedLyrics")]
    synced_lyrics: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::{LyricLine, current_lyric, parse_lrc};

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
