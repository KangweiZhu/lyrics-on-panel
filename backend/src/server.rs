use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    Router,
    extract::{
        State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    response::Response,
    routing::get,
};
use serde::Deserialize;
use serde_json::json;
use tokio::sync::{RwLock, Semaphore};

use crate::{
    lxmusic::LxMusicManager,
    lyrics::{LyricsManager, current_lyric},
    model::{
        LyricsResponse, PlaybackStatus, PlayerResponse, PlayerState, PollState, TrackResponse,
    },
    mpris::PlayerRegistry,
};

#[derive(Clone)]
struct AppState {
    registry: Arc<PlayerRegistry>,
    lyrics: Arc<LyricsManager>,
    lxmusic: Arc<LxMusicManager>,
    poll_connections: Arc<Semaphore>,
    control_connections: Arc<Semaphore>,
    last_polled_player: Arc<RwLock<Option<String>>>,
}

pub async fn serve(
    registry: Arc<PlayerRegistry>,
    lyrics: Arc<LyricsManager>,
    lxmusic: Arc<LxMusicManager>,
) -> anyhow::Result<()> {
    let app = app_router(AppState {
        registry,
        lyrics,
        lxmusic,
        poll_connections: Arc::new(Semaphore::new(16)),
        control_connections: Arc::new(Semaphore::new(16)),
        last_polled_player: Arc::new(RwLock::new(None)),
    });
    let listener = tokio::net::TcpListener::bind("127.0.0.1:23560").await?;
    axum::serve(listener, app).await?;
    Ok(())
}

fn app_router(state: AppState) -> Router {
    Router::new()
        .route("/healthcheck", get(healthcheck))
        .route("/poll", get(poll))
        .route("/control", get(control))
        .fallback(get(unknown_endpoint))
        .with_state(state)
}

async fn unknown_endpoint(ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(|mut socket| async move {
        let _ = socket
            .send(Message::Close(Some(axum::extract::ws::CloseFrame {
                code: 1008,
                reason: "Unknown endpoint".into(),
            })))
            .await;
    })
}

async fn healthcheck(ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(|mut socket| async move {
        if socket
            .send(Message::Text(json!({ "status": "ok" }).to_string().into()))
            .await
            .is_ok()
        {
            let _ = socket
                .send(Message::Close(Some(axum::extract::ws::CloseFrame {
                    code: 1000,
                    reason: "Normal closure".into(),
                })))
                .await;
        }
    })
}

async fn poll(ws: WebSocketUpgrade, State(state): State<AppState>) -> Response {
    ws.on_upgrade(move |socket| poll_socket(socket, state))
}

async fn poll_socket(mut socket: WebSocket, state: AppState) {
    let Ok(_permit) = Arc::clone(&state.poll_connections).try_acquire_owned() else {
        let _ = socket
            .send(Message::Close(Some(axum::extract::ws::CloseFrame {
                code: 1013,
                reason: "Too many poll connections".into(),
            })))
            .await;
        return;
    };
    let mut current_selection: Option<String> = None;
    let mut limiter = ResponseLimiter::new();
    while let Some(Ok(message)) = socket.recv().await {
        let Some(message) = json_message_bytes(&message) else {
            continue;
        };
        limiter.wait().await;
        let request: PollRequest = match serde_json::from_slice(message) {
            Ok(request) => request,
            Err(_) => {
                if send_json(&mut socket, &json!({ "error": "Invalid JSON" }))
                    .await
                    .is_err()
                {
                    break;
                }
                limiter.defer(Duration::from_secs(1));
                continue;
            }
        };
        let players = state.registry.snapshot().await;
        let available_players = players
            .iter()
            .map(|player| player.bus_name.clone())
            .collect();
        let selected = select_player(&players, request.player.as_deref(), &mut current_selection);
        if let Some(player) = selected {
            *state.last_polled_player.write().await = Some(player.bus_name.clone());
        }
        let response = match selected {
            Some(player) => {
                let position_us = player.position_us(Instant::now());
                let current_lyric = if player.identity == "lx-music-desktop" {
                    state
                        .lxmusic
                        .current_lyric(
                            request.lx_music_port.unwrap_or(23330),
                            &player.track.title,
                            position_us,
                        )
                        .await
                } else {
                    state
                        .lyrics
                        .get_or_schedule(player)
                        .await
                        .as_deref()
                        .and_then(|lines| current_lyric(lines, position_us))
                };
                PollState {
                    playback_status: player.playback_status.as_str(),
                    player: Some(PlayerResponse {
                        identity: player.identity.clone(),
                        bus_name: player.bus_name.clone(),
                    }),
                    track: Some(TrackResponse {
                        title: player.track.title.clone(),
                        artist: player.track.artists.join(", "),
                        album: player.track.album.clone(),
                        duration: player.track.duration_us,
                    }),
                    position_ms: position_us,
                    lyrics: Some(LyricsResponse { current_lyric }),
                    available_players,
                }
            }
            None => PollState::empty(available_players),
        };
        if send_json(&mut socket, &response).await.is_err() {
            break;
        }
        limiter.defer(poll_interval(response.playback_status));
    }
}

fn poll_interval(status: &str) -> Duration {
    if status == "playing" {
        Duration::from_millis(250)
    } else {
        Duration::from_secs(1)
    }
}

fn select_player<'a>(
    players: &'a [PlayerState],
    requested: Option<&str>,
    current: &mut Option<String>,
) -> Option<&'a PlayerState> {
    if let Some(requested) = requested.filter(|name| !name.is_empty()) {
        let selected = if requested == "lx-music-desktop" {
            players.iter().find(|player| player.identity == requested)
        } else {
            players.iter().find(|player| player.bus_name == requested)
        };
        *current = selected.map(|player| player.bus_name.clone());
        return selected;
    }

    let current_player = current
        .as_ref()
        .and_then(|name| players.iter().find(|player| &player.bus_name == name));
    let selected = match current_player {
        Some(player) if player.playback_status == PlaybackStatus::Playing => Some(player),
        Some(player) => players
            .iter()
            .find(|candidate| candidate.playback_status == PlaybackStatus::Playing)
            .or(Some(player)),
        None => players
            .iter()
            .find(|player| player.playback_status == PlaybackStatus::Playing)
            .or_else(|| players.first()),
    };
    *current = selected.map(|player| player.bus_name.clone());
    selected
}

fn select_control_player<'a>(
    players: &'a [PlayerState],
    requested: Option<&str>,
    last_polled_player: Option<&str>,
) -> Option<&'a PlayerState> {
    if requested.is_some_and(|name| !name.is_empty()) {
        let mut current = None;
        return select_player(players, requested, &mut current);
    }
    last_polled_player
        .and_then(|name| players.iter().find(|player| player.bus_name == name))
        .or_else(|| {
            let mut current = None;
            select_player(players, None, &mut current)
        })
}

async fn control(ws: WebSocketUpgrade, State(state): State<AppState>) -> Response {
    ws.on_upgrade(move |socket| control_socket(socket, state))
}

async fn control_socket(mut socket: WebSocket, state: AppState) {
    let Ok(_permit) = Arc::clone(&state.control_connections).try_acquire_owned() else {
        let _ = socket
            .send(Message::Close(Some(axum::extract::ws::CloseFrame {
                code: 1013,
                reason: "Too many control connections".into(),
            })))
            .await;
        return;
    };
    let mut limiter = ResponseLimiter::new();
    while let Some(Ok(message)) = socket.recv().await {
        let Some(message) = json_message_bytes(&message) else {
            continue;
        };
        limiter.wait().await;
        let request: ControlRequest = match serde_json::from_slice(message) {
            Ok(request) => request,
            Err(_) => {
                if send_json(&mut socket, &json!({ "error": "Invalid JSON" }))
                    .await
                    .is_err()
                {
                    break;
                }
                limiter.defer(Duration::from_secs(1));
                continue;
            }
        };
        let players = state.registry.snapshot().await;
        let last_polled_player = state.last_polled_player.read().await.clone();
        let selected = select_control_player(
            &players,
            request.player.as_deref(),
            last_polled_player.as_deref(),
        )
        .map(|player| player.bus_name.clone());
        let success = match (selected, request.action.as_deref()) {
            (Some(bus_name), Some(action)) => state.registry.control(&bus_name, action).await,
            _ => false,
        };
        if send_json(&mut socket, &json!({ "success": success }))
            .await
            .is_err()
        {
            break;
        }
        limiter.defer(Duration::from_millis(100));
    }
}

struct ResponseLimiter {
    next_response_at: tokio::time::Instant,
}

impl ResponseLimiter {
    fn new() -> Self {
        Self {
            next_response_at: tokio::time::Instant::now(),
        }
    }

    async fn wait(&self) {
        tokio::time::sleep_until(self.next_response_at).await;
    }

    fn defer(&mut self, delay: Duration) {
        self.next_response_at = tokio::time::Instant::now() + delay;
    }
}

fn json_message_bytes(message: &Message) -> Option<&[u8]> {
    match message {
        Message::Text(text) => Some(text.as_bytes()),
        Message::Binary(bytes) => Some(bytes.as_ref()),
        _ => None,
    }
}

async fn send_json(
    socket: &mut WebSocket,
    value: &impl serde::Serialize,
) -> Result<(), axum::Error> {
    let text = serde_json::to_string(value).expect("serializable websocket response");
    socket.send(Message::Text(text.into())).await
}

#[derive(Deserialize)]
struct PollRequest {
    player: Option<String>,
    #[serde(rename = "lxMusicPort")]
    lx_music_port: Option<u16>,
}

#[derive(Deserialize)]
struct ControlRequest {
    action: Option<String>,
    player: Option<String>,
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use axum::{Router, extract::ws::Message, routing::get};
    use futures_util::StreamExt;
    use tokio_tungstenite::{
        connect_async,
        tungstenite::{Message as TungsteniteMessage, protocol::frame::coding::CloseCode},
    };

    use crate::model::{PlaybackStatus, PlayerState, Track};

    use super::{
        ControlRequest, PollRequest, ResponseLimiter, healthcheck, json_message_bytes,
        poll_interval, select_control_player, select_player, unknown_endpoint,
    };

    fn player(bus_name: &str, identity: &str, status: PlaybackStatus) -> PlayerState {
        PlayerState {
            bus_name: bus_name.into(),
            identity: identity.into(),
            track: Track::default(),
            playback_status: status,
            rate: 1.0,
            base_position_us: 0,
            position_updated_at: Instant::now(),
        }
    }

    #[test]
    fn strict_and_alias_selection_do_not_fallback() {
        let players = vec![
            player(
                "org.mpris.MediaPlayer2.spotify",
                "Spotify",
                PlaybackStatus::Playing,
            ),
            player(
                "org.mpris.MediaPlayer2.chromium.instance",
                "lx-music-desktop",
                PlaybackStatus::Paused,
            ),
        ];
        let mut current = None;
        assert!(select_player(&players, Some("missing"), &mut current).is_none());
        assert_eq!(
            select_player(&players, Some("lx-music-desktop"), &mut current)
                .unwrap()
                .bus_name,
            "org.mpris.MediaPlayer2.chromium.instance"
        );
    }

    #[test]
    fn global_selection_keeps_current_playing_player_and_uses_stable_fallback() {
        let players = vec![
            player("first", "First", PlaybackStatus::Playing),
            player("second", "Second", PlaybackStatus::Playing),
        ];
        let mut current = Some("second".into());
        assert_eq!(
            select_player(&players, None, &mut current)
                .unwrap()
                .bus_name,
            "second"
        );
        assert_eq!(current.as_deref(), Some("second"));

        let paused = vec![
            player("first", "First", PlaybackStatus::Paused),
            player("second", "Second", PlaybackStatus::Stopped),
        ];
        assert_eq!(
            select_player(&paused, None, &mut None).unwrap().bus_name,
            "first"
        );

        let switching = vec![
            player("first", "First", PlaybackStatus::Playing),
            player("second", "Second", PlaybackStatus::Paused),
        ];
        assert_eq!(
            select_player(&switching, None, &mut current)
                .unwrap()
                .bus_name,
            "first"
        );
    }

    #[test]
    fn control_without_player_prefers_last_poll_then_global_fallback() {
        let players = vec![
            player("first", "First", PlaybackStatus::Playing),
            player("last-polled", "Last", PlaybackStatus::Paused),
        ];
        assert_eq!(
            select_control_player(&players, None, Some("last-polled"))
                .unwrap()
                .bus_name,
            "last-polled"
        );
        assert_eq!(
            select_control_player(&players, None, Some("gone"))
                .unwrap()
                .bus_name,
            "first"
        );
    }

    #[test]
    fn explicit_control_player_remains_strict() {
        let players = vec![player("first", "First", PlaybackStatus::Playing)];
        assert!(select_control_player(&players, Some("missing"), Some("first")).is_none());
    }

    #[test]
    fn server_caps_poll_rate_even_for_unthrottled_clients() {
        assert_eq!(poll_interval("playing"), Duration::from_millis(250));
        assert_eq!(poll_interval("paused"), Duration::from_secs(1));
        assert_eq!(poll_interval("stopped"), Duration::from_secs(1));
    }

    #[tokio::test(start_paused = true)]
    async fn response_limiter_spaces_burst_requests() {
        let mut limiter = ResponseLimiter::new();
        limiter.wait().await;
        limiter.defer(Duration::from_millis(250));
        let started = tokio::time::Instant::now();

        limiter.wait().await;

        assert_eq!(started.elapsed(), Duration::from_millis(250));
    }

    #[test]
    fn text_and_binary_frames_decode_identical_json() {
        let text = Message::Text(r#"{"player":"test","lxMusicPort":23330}"#.into());
        let binary =
            Message::Binary(r#"{"action":"pause","player":"test"}"#.as_bytes().to_vec().into());

        let poll: PollRequest = serde_json::from_slice(json_message_bytes(&text).unwrap()).unwrap();
        let control: ControlRequest =
            serde_json::from_slice(json_message_bytes(&binary).unwrap()).unwrap();

        assert_eq!(poll.player.as_deref(), Some("test"));
        assert_eq!(poll.lx_music_port, Some(23330));
        assert_eq!(control.action.as_deref(), Some("pause"));
        assert_eq!(control.player.as_deref(), Some("test"));
        assert!(json_message_bytes(&Message::Ping(Vec::new().into())).is_none());
        assert!(serde_json::from_slice::<PollRequest>(b"not json").is_err());
    }

    async fn spawn_protocol_server() -> (String, tokio::task::JoinHandle<()>) {
        let app = Router::new()
            .route("/healthcheck", get(healthcheck))
            .fallback(get(unknown_endpoint));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        (format!("ws://{address}"), task)
    }

    #[tokio::test]
    async fn healthcheck_sends_text_then_normal_close() {
        let (base, server) = spawn_protocol_server().await;
        let (mut socket, _) = connect_async(format!("{base}/healthcheck")).await.unwrap();

        let response = socket.next().await.unwrap().unwrap();
        assert_eq!(response.into_text().unwrap(), r#"{"status":"ok"}"#);
        let close = socket.next().await.unwrap().unwrap();
        let TungsteniteMessage::Close(Some(frame)) = close else {
            panic!("expected close frame");
        };
        assert_eq!(frame.code, CloseCode::Normal);
        server.abort();
    }

    #[tokio::test]
    async fn unknown_endpoint_closes_with_policy_violation() {
        let (base, server) = spawn_protocol_server().await;
        let (mut socket, _) = connect_async(format!("{base}/missing")).await.unwrap();

        let close = socket.next().await.unwrap().unwrap();
        let TungsteniteMessage::Close(Some(frame)) = close else {
            panic!("expected close frame");
        };
        assert_eq!(frame.code, CloseCode::Policy);
        server.abort();
    }
}
