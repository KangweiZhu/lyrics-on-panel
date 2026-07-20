use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};

use futures_util::StreamExt;
use reqwest::Client;
use serde_json::{Map, Value};
use tokio::{sync::RwLock, task::AbortHandle};

use crate::lyrics::{current_lyric, parse_lrc};

const FILTER: &str =
    "status,name,singer,albumName,duration,progress,playbackRate,lyricLineText,lyric";
const MAX_SUBSCRIPTIONS: usize = 16;
const IDLE_SUBSCRIPTION_AGE: Duration = Duration::from_secs(30 * 60);

pub struct LxMusicManager {
    client: Client,
    subscriptions: RwLock<HashMap<u16, Subscription>>,
}

struct Subscription {
    state: Arc<RwLock<PlayerStatus>>,
    abort_handle: AbortHandle,
    last_requested: Instant,
}

#[derive(Clone, Debug, Default, PartialEq)]
struct PlayerStatus {
    status: Option<PlaybackStatus>,
    name: Option<String>,
    singer: Option<String>,
    album_name: Option<String>,
    duration: Option<f64>,
    progress: Option<f64>,
    playback_rate: Option<f64>,
    lyric_line_text: Option<String>,
    lyric: Option<String>,
    parsed_lyric: Option<Arc<Vec<crate::lyrics::LyricLine>>>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum PlaybackStatus {
    Playing,
    Paused,
    Error,
    Stoped,
}

impl LxMusicManager {
    pub fn new() -> Result<Arc<Self>, reqwest::Error> {
        Ok(Arc::new(Self {
            client: Client::builder()
                .connect_timeout(Duration::from_secs(5))
                .user_agent("lyrics-on-panel/0.1")
                .build()?,
            subscriptions: RwLock::new(HashMap::new()),
        }))
    }

    pub async fn current_lyric(
        self: &Arc<Self>,
        port: u16,
        track_title: &str,
        position_us: i64,
    ) -> Option<String> {
        let state = self.ensure_subscription(port).await;
        state.read().await.current_lyric(track_title, position_us)
    }

    async fn ensure_subscription(self: &Arc<Self>, port: u16) -> Arc<RwLock<PlayerStatus>> {
        let mut subscriptions = self.subscriptions.write().await;
        Self::remove_stale_subscriptions(&mut subscriptions);
        if let Some(subscription) = subscriptions.get_mut(&port) {
            subscription.last_requested = Instant::now();
            return Arc::clone(&subscription.state);
        }
        if subscriptions.len() >= MAX_SUBSCRIPTIONS {
            Self::remove_oldest_subscription(&mut subscriptions);
        }

        let state = Arc::new(RwLock::new(PlayerStatus::default()));
        let manager = Arc::clone(self);
        let task_state = Arc::clone(&state);
        let task = tokio::spawn(async move {
            manager.run_subscription(port, task_state).await;
        });
        subscriptions.insert(
            port,
            Subscription {
                state: Arc::clone(&state),
                abort_handle: task.abort_handle(),
                last_requested: Instant::now(),
            },
        );
        state
    }

    fn remove_stale_subscriptions(subscriptions: &mut HashMap<u16, Subscription>) {
        let now = Instant::now();
        subscriptions.retain(|_, subscription| {
            let keep =
                now.saturating_duration_since(subscription.last_requested) < IDLE_SUBSCRIPTION_AGE;
            if !keep {
                subscription.abort_handle.abort();
            }
            keep
        });
    }

    fn remove_oldest_subscription(subscriptions: &mut HashMap<u16, Subscription>) {
        let oldest_port = subscriptions
            .iter()
            .min_by_key(|(_, subscription)| subscription.last_requested)
            .map(|(port, _)| *port);
        if let Some(port) = oldest_port
            && let Some(subscription) = subscriptions.remove(&port)
        {
            subscription.abort_handle.abort();
        }
    }

    async fn run_subscription(&self, port: u16, state: Arc<RwLock<PlayerStatus>>) {
        let mut retry_delay = Duration::from_secs(1);
        loop {
            self.reconcile_snapshot(port, &state).await;
            let result = self.consume_events(port, &state, &mut retry_delay).await;
            self.reconcile_snapshot(port, &state).await;
            if let Err(error) = result {
                eprintln!("LX Music SSE connection on port {port} ended: {error:#}");
            }
            tokio::time::sleep(retry_delay).await;
            retry_delay = (retry_delay * 2).min(Duration::from_secs(30));
        }
    }

    async fn reconcile_snapshot(&self, port: u16, state: &RwLock<PlayerStatus>) {
        let url = format!("http://127.0.0.1:{port}/status");
        let snapshot = tokio::time::timeout(Duration::from_secs(5), async {
            self.client
                .get(url)
                .query(&[("filter", FILTER)])
                .send()
                .await?
                .error_for_status()?
                .json::<Map<String, Value>>()
                .await
        })
        .await;
        let Ok(Ok(fields)) = snapshot else {
            return;
        };
        state.write().await.apply_fields(fields);
    }

    async fn consume_events(
        &self,
        port: u16,
        state: &RwLock<PlayerStatus>,
        retry_delay: &mut Duration,
    ) -> anyhow::Result<()> {
        let url = format!("http://127.0.0.1:{port}/subscribe-player-status");
        let response = tokio::time::timeout(
            Duration::from_secs(5),
            self.client.get(url).query(&[("filter", FILTER)]).send(),
        )
        .await??
        .error_for_status()?;
        self.reconcile_snapshot(port, state).await;
        let mut stream = response.bytes_stream();
        let mut parser = SseParser::default();
        while let Some(chunk) = stream.next().await {
            for event in parser.push(&chunk?) {
                if let Some((field, value)) = event.into_field() {
                    *retry_delay = Duration::from_secs(1);
                    state.write().await.apply_field(&field, value);
                }
            }
        }
        anyhow::bail!("event stream closed")
    }
}

impl PlayerStatus {
    fn apply_fields(&mut self, mut fields: Map<String, Value>) {
        for field in ["name", "singer", "albumName"] {
            if let Some(value) = fields.remove(field) {
                self.apply_field(field, value);
            }
        }
        for (field, value) in fields {
            self.apply_field(&field, value);
        }
    }

    fn apply_field(&mut self, field: &str, value: Value) {
        if matches!(field, "name" | "singer" | "albumName") {
            let identity_value = value.as_str().map(str::to_owned);
            let changed = match field {
                "name" => self.name != identity_value,
                "singer" => self.singer != identity_value,
                "albumName" => self.album_name != identity_value,
                _ => false,
            };
            if changed {
                self.lyric_line_text = None;
                self.lyric = None;
                self.parsed_lyric = None;
            }
            match field {
                "name" => self.name = identity_value,
                "singer" => self.singer = identity_value,
                "albumName" => self.album_name = identity_value,
                _ => {}
            }
            return;
        }

        match field {
            "status" => self.status = value.as_str().and_then(PlaybackStatus::parse),
            "duration" => self.duration = value.as_f64(),
            "progress" => self.progress = value.as_f64(),
            "playbackRate" => self.playback_rate = value.as_f64(),
            "lyricLineText" => self.lyric_line_text = nonempty_string(&value),
            "lyric" => {
                self.lyric = nonempty_string(&value);
                self.parsed_lyric = self.lyric.as_deref().and_then(parse_lrc).map(Arc::new);
            }
            _ => {}
        }
    }

    fn current_lyric(&self, track_title: &str, position_us: i64) -> Option<String> {
        if self.name.as_deref() != Some(track_title) {
            return None;
        }
        self.lyric_line_text.clone().or_else(|| {
            self.parsed_lyric
                .as_deref()
                .and_then(|lines| current_lyric(lines, position_us))
        })
    }
}

impl PlaybackStatus {
    fn parse(value: &str) -> Option<Self> {
        match value {
            "playing" => Some(Self::Playing),
            "paused" => Some(Self::Paused),
            "error" => Some(Self::Error),
            "stoped" => Some(Self::Stoped),
            _ => None,
        }
    }
}

fn nonempty_string(value: &Value) -> Option<String> {
    value
        .as_str()
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

#[derive(Debug, Default)]
struct SseParser {
    buffer: Vec<u8>,
    event: Option<String>,
    data: Vec<String>,
}

#[derive(Debug, Eq, PartialEq)]
struct SseEvent {
    event: Option<String>,
    data: String,
}

impl SseParser {
    fn push(&mut self, chunk: &[u8]) -> Vec<SseEvent> {
        self.buffer.extend_from_slice(chunk);
        let mut events = Vec::new();
        while let Some(newline) = self.buffer.iter().position(|byte| *byte == b'\n') {
            let mut line = self.buffer.drain(..=newline).collect::<Vec<_>>();
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
            self.process_line(&String::from_utf8_lossy(&line), &mut events);
        }
        events
    }

    fn process_line(&mut self, line: &str, events: &mut Vec<SseEvent>) {
        if line.is_empty() {
            if !self.data.is_empty() {
                events.push(SseEvent {
                    event: self.event.take(),
                    data: self.data.join("\n"),
                });
                self.data.clear();
            } else {
                self.event = None;
            }
            return;
        }
        if line.starts_with(':') {
            return;
        }
        let (field, value) = line.split_once(':').unwrap_or((line, ""));
        let value = value.strip_prefix(' ').unwrap_or(value);
        match field {
            "event" => self.event = Some(value.to_owned()),
            "data" => self.data.push(value.to_owned()),
            _ => {}
        }
    }
}

impl SseEvent {
    fn into_field(self) -> Option<(String, Value)> {
        let field = self.event?;
        let value = serde_json::from_str(&self.data).ok()?;
        Some((field, value))
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use serde_json::{Map, json};

    use super::{LxMusicManager, MAX_SUBSCRIPTIONS, PlayerStatus, SseEvent, SseParser};

    #[test]
    fn parses_chunk_boundaries_crlf_comments_and_multiple_events() {
        let mut parser = SseParser::default();
        assert!(parser.push(b": keepalive\r\nevent: na").is_empty());
        assert!(parser.push(b"me\r\ndata: \"").is_empty());
        assert_eq!(
            parser.push(b"Song\"\r\n\r\nevent: progress\ndata: 12.5\n\n"),
            vec![
                SseEvent {
                    event: Some("name".into()),
                    data: "\"Song\"".into(),
                },
                SseEvent {
                    event: Some("progress".into()),
                    data: "12.5".into(),
                },
            ]
        );
    }

    #[test]
    fn song_change_clears_old_lyrics_before_new_lyrics_arrive() {
        let mut status = PlayerStatus {
            name: Some("Old Song".into()),
            lyric_line_text: Some("old line".into()),
            lyric: Some("[00:01]old lyric".into()),
            ..PlayerStatus::default()
        };
        status.apply_field("name", json!("New Song"));
        assert_eq!(status.name.as_deref(), Some("New Song"));
        assert_eq!(status.lyric_line_text, None);
        assert_eq!(status.lyric, None);
    }

    #[test]
    fn same_title_with_new_singer_or_album_clears_old_lyrics() {
        let mut status = PlayerStatus {
            name: Some("Song".into()),
            singer: Some("Old Artist".into()),
            album_name: Some("Old Album".into()),
            lyric_line_text: Some("old line".into()),
            lyric: Some("[00:01]old lyric".into()),
            ..PlayerStatus::default()
        };

        status.apply_field("singer", json!("New Artist"));
        assert_eq!(status.lyric_line_text, None);
        assert_eq!(status.lyric, None);

        status.lyric_line_text = Some("another old line".into());
        status.lyric = Some("[00:01]another old lyric".into());
        status.apply_field("albumName", json!("New Album"));
        assert_eq!(status.lyric_line_text, None);
        assert_eq!(status.lyric, None);
    }

    #[test]
    fn snapshot_applies_identity_before_new_lyrics() {
        let mut status = PlayerStatus {
            name: Some("Song".into()),
            singer: Some("Old Artist".into()),
            lyric_line_text: Some("old line".into()),
            ..PlayerStatus::default()
        };
        let mut fields = Map::new();
        fields.insert("lyricLineText".into(), json!("new line"));
        fields.insert("singer".into(), json!("New Artist"));
        fields.insert("name".into(), json!("Song"));

        status.apply_fields(fields);

        assert_eq!(status.singer.as_deref(), Some("New Artist"));
        assert_eq!(status.lyric_line_text.as_deref(), Some("new line"));
    }

    #[test]
    fn late_lyric_line_becomes_visible_without_refetch() {
        let mut status = PlayerStatus {
            name: Some("Song".into()),
            ..PlayerStatus::default()
        };
        assert_eq!(status.current_lyric("Song", 2_000_000), None);
        status.apply_field("lyricLineText", json!("late line"));
        assert_eq!(
            status.current_lyric("Song", 2_000_000).as_deref(),
            Some("late line")
        );
    }

    #[test]
    fn title_mismatch_never_returns_lyrics() {
        let status = PlayerStatus {
            name: Some("Different Song".into()),
            lyric_line_text: Some("wrong line".into()),
            lyric: Some("[00:01]wrong lyric".into()),
            ..PlayerStatus::default()
        };
        assert_eq!(status.current_lyric("MPRIS Song", 2_000_000), None);
    }

    #[test]
    fn full_lyric_is_used_until_current_line_arrives() {
        let mut fields = Map::new();
        fields.insert("name".into(), json!("Song"));
        fields.insert("lyric".into(), json!("[00:01]first\n[00:03]third"));
        let mut status = PlayerStatus::default();
        status.apply_fields(fields);
        assert_eq!(
            status.current_lyric("Song", 2_000_000).as_deref(),
            Some("first")
        );
        status.apply_field("lyricLineText", json!("live line"));
        assert_eq!(
            status.current_lyric("Song", 2_000_000).as_deref(),
            Some("live line")
        );
    }

    #[tokio::test]
    async fn concurrent_ports_share_tasks_and_stay_bounded() {
        let manager = LxMusicManager::new().unwrap();
        let mut requests = Vec::new();
        for port in 30_000..30_000 + MAX_SUBSCRIPTIONS as u16 + 8 {
            let manager = Arc::clone(&manager);
            requests.push(tokio::spawn(async move {
                manager.ensure_subscription(port).await;
            }));
        }
        for request in requests {
            request.await.unwrap();
        }

        let subscriptions = manager.subscriptions.read().await;
        assert_eq!(subscriptions.len(), MAX_SUBSCRIPTIONS);
        let port = *subscriptions.keys().next().unwrap();
        let original_state = Arc::clone(&subscriptions[&port].state);
        drop(subscriptions);
        let shared_state = manager.ensure_subscription(port).await;
        assert!(Arc::ptr_eq(&original_state, &shared_state));
    }
}
