use std::time::Instant;

use serde::Serialize;

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Track {
    pub title: String,
    pub artists: Vec<String>,
    pub album: String,
    pub duration_us: i64,
    pub track_id: String,
    pub url: String,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum PlaybackStatus {
    Playing,
    Paused,
    #[default]
    Stopped,
}

impl PlaybackStatus {
    pub fn parse(value: &str) -> Self {
        match value {
            "Playing" => Self::Playing,
            "Paused" => Self::Paused,
            _ => Self::Stopped,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Playing => "playing",
            Self::Paused => "paused",
            Self::Stopped => "stopped",
        }
    }
}

#[derive(Clone, Debug)]
pub struct PlayerState {
    pub bus_name: String,
    pub identity: String,
    pub track: Track,
    pub playback_status: PlaybackStatus,
    pub rate: f64,
    pub base_position_us: i64,
    pub position_updated_at: Instant,
}

impl PlayerState {
    pub fn position_us(&self, now: Instant) -> i64 {
        let elapsed = if self.playback_status == PlaybackStatus::Playing {
            now.saturating_duration_since(self.position_updated_at)
                .as_micros() as f64
                * self.rate
        } else {
            0.0
        };
        let position = self.base_position_us.saturating_add(elapsed as i64).max(0);
        if self.track.duration_us > 0 {
            position.min(self.track.duration_us)
        } else {
            position
        }
    }

    pub fn rebase(&mut self, now: Instant) {
        self.base_position_us = self.position_us(now);
        self.position_updated_at = now;
    }
}

#[derive(Serialize)]
pub struct PollState {
    pub playback_status: &'static str,
    pub player: Option<PlayerResponse>,
    pub track: Option<TrackResponse>,
    pub position_ms: i64,
    pub lyrics: Option<LyricsResponse>,
    pub available_players: Vec<String>,
}

impl PollState {
    pub fn empty(available_players: Vec<String>) -> Self {
        Self {
            playback_status: "stopped",
            player: None,
            track: None,
            position_ms: 0,
            lyrics: None,
            available_players,
        }
    }
}

#[derive(Serialize)]
pub struct PlayerResponse {
    pub identity: String,
    pub bus_name: String,
}

#[derive(Serialize)]
pub struct TrackResponse {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: i64,
}

#[derive(Serialize)]
pub struct LyricsResponse {
    pub current_lyric: Option<String>,
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use serde_json::json;

    use super::{
        LyricsResponse, PlaybackStatus, PlayerResponse, PlayerState, PollState, Track,
        TrackResponse,
    };

    fn state(status: PlaybackStatus, rate: f64, position: i64, duration: i64) -> PlayerState {
        PlayerState {
            bus_name: String::new(),
            identity: String::new(),
            track: Track {
                duration_us: duration,
                ..Track::default()
            },
            playback_status: status,
            rate,
            base_position_us: position,
            position_updated_at: Instant::now() - Duration::from_secs(2),
        }
    }

    #[test]
    fn playing_position_uses_elapsed_time_and_rate() {
        let state = state(PlaybackStatus::Playing, 1.5, 1_000_000, 10_000_000);
        let position = state.position_us(Instant::now());
        assert!((3_900_000..=4_100_000).contains(&position));
    }

    #[test]
    fn paused_position_does_not_advance_and_playing_is_capped() {
        let paused = state(PlaybackStatus::Paused, 1.0, 1_000_000, 2_000_000);
        assert_eq!(paused.position_us(Instant::now()), 1_000_000);

        let playing = state(PlaybackStatus::Playing, 1.0, 1_000_000, 2_000_000);
        assert_eq!(playing.position_us(Instant::now()), 2_000_000);
    }

    #[test]
    fn poll_response_keeps_python_compatible_schema() {
        let response = PollState {
            playback_status: "playing",
            player: Some(PlayerResponse {
                identity: "Test".into(),
                bus_name: "org.mpris.MediaPlayer2.test".into(),
            }),
            track: Some(TrackResponse {
                title: "Song".into(),
                artist: "Artist".into(),
                album: "Album".into(),
                duration: 3_000_000,
            }),
            position_ms: 1_000_000,
            lyrics: Some(LyricsResponse {
                current_lyric: Some("line".into()),
            }),
            available_players: vec!["org.mpris.MediaPlayer2.test".into()],
        };

        assert_eq!(
            serde_json::to_value(response).unwrap(),
            json!({
                "playback_status": "playing",
                "player": {
                    "identity": "Test",
                    "bus_name": "org.mpris.MediaPlayer2.test"
                },
                "track": {
                    "title": "Song",
                    "artist": "Artist",
                    "album": "Album",
                    "duration": 3_000_000
                },
                "position_ms": 1_000_000,
                "lyrics": { "current_lyric": "line" },
                "available_players": ["org.mpris.MediaPlayer2.test"]
            })
        );
    }
}
