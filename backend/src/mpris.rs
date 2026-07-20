use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use anyhow::{Context, Result};
use futures_util::{StreamExt, future::BoxFuture};
use tokio::{
    sync::{Mutex, RwLock, oneshot},
    task::JoinHandle,
};
use zbus::{Connection, Proxy, fdo, names::BusName};
use zvariant::{OwnedObjectPath, OwnedValue};

use crate::model::{PlaybackStatus, PlayerState, Track};

const MPRIS_PREFIX: &str = "org.mpris.MediaPlayer2.";
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const ROOT_IFACE: &str = "org.mpris.MediaPlayer2";
const PLAYER_IFACE: &str = "org.mpris.MediaPlayer2.Player";
const PROPERTIES_IFACE: &str = "org.freedesktop.DBus.Properties";
const WATCHER_RESTART_DELAY: Duration = Duration::from_secs(1);
const OWNER_RETRY_MAX_DELAY: Duration = Duration::from_secs(30);
const POSITION_RECONCILIATION_INTERVAL: Duration = Duration::from_secs(5);

struct PlayerWatcher {
    id: u64,
    handle: JoinHandle<()>,
}

struct PlayerOwner {
    order: u64,
    unique_name: Option<String>,
    generation: u64,
    watcher: Option<PlayerWatcher>,
    restart_delay: Duration,
}

pub struct PlayerRegistry {
    connection: Connection,
    players: RwLock<Vec<PlayerState>>,
    owners: Mutex<HashMap<String, PlayerOwner>>,
    owner_reconciliation: Mutex<()>,
    owner_retries: Mutex<HashSet<String>>,
    next_owner_order: AtomicU64,
    next_watcher_id: AtomicU64,
}

impl PlayerRegistry {
    pub async fn start() -> Result<Arc<Self>> {
        let connection = Connection::session()
            .await
            .context("connect to the session D-Bus")?;
        let registry = Arc::new(Self {
            connection,
            players: RwLock::new(Vec::new()),
            owners: Mutex::new(HashMap::new()),
            owner_reconciliation: Mutex::new(()),
            owner_retries: Mutex::new(HashSet::new()),
            next_owner_order: AtomicU64::new(0),
            next_watcher_id: AtomicU64::new(1),
        });

        let dbus = fdo::DBusProxy::new(&registry.connection).await?;
        let owner_changes = dbus.receive_name_owner_changed().await?;
        for name in dbus.list_names().await? {
            let name = name.as_str();
            if name.starts_with(MPRIS_PREFIX) {
                registry.reconcile_owner(name).await;
            }
        }
        registry.spawn_name_watcher(owner_changes);
        registry.spawn_position_reconciliation();
        Ok(registry)
    }

    fn spawn_name_watcher(self: &Arc<Self>, mut stream: fdo::NameOwnerChangedStream) {
        let registry = Arc::clone(self);
        tokio::spawn(async move {
            loop {
                while let Some(signal) = stream.next().await {
                    let args = match signal.args() {
                        Ok(args) => args,
                        Err(error) => {
                            eprintln!("invalid D-Bus NameOwnerChanged signal: {error}");
                            continue;
                        }
                    };
                    let name = args.name().as_str();
                    if name.starts_with(MPRIS_PREFIX) {
                        let new_owner = args
                            .new_owner()
                            .as_ref()
                            .map(|owner| owner.as_str().to_owned());
                        registry.reconcile_known_owner(name, new_owner).await;
                    }
                }
                eprintln!("D-Bus NameOwnerChanged stream ended; recreating it");
                tokio::time::sleep(WATCHER_RESTART_DELAY).await;

                let dbus = match fdo::DBusProxy::new(&registry.connection).await {
                    Ok(dbus) => dbus,
                    Err(error) => {
                        eprintln!("failed to recreate D-Bus proxy: {error}");
                        continue;
                    }
                };
                match dbus.receive_name_owner_changed().await {
                    Ok(new_stream) => stream = new_stream,
                    Err(error) => {
                        eprintln!("failed to recreate D-Bus NameOwnerChanged stream: {error}");
                        continue;
                    }
                }
                match dbus.list_names().await {
                    Ok(names) => {
                        let bus_names: Vec<String> = names
                            .into_iter()
                            .filter_map(|name| {
                                let name = name.as_str();
                                name.starts_with(MPRIS_PREFIX).then(|| name.to_owned())
                            })
                            .collect();
                        let listed: HashSet<&str> = bus_names.iter().map(String::as_str).collect();
                        let missing_known: Vec<String> = registry
                            .owners
                            .lock()
                            .await
                            .keys()
                            .filter(|name| !listed.contains(name.as_str()))
                            .cloned()
                            .collect();
                        for name in bus_names.into_iter().chain(missing_known) {
                            registry.reconcile_owner(&name).await;
                        }
                    }
                    Err(error) => eprintln!("failed to list D-Bus names after reconnect: {error}"),
                }
            }
        });
    }

    async fn reconcile_owner(self: &Arc<Self>, bus_name: &str) {
        match self.current_owner(bus_name).await {
            Ok(owner) => self.reconcile_known_owner(bus_name, owner).await,
            Err(error) => {
                eprintln!("failed to query D-Bus owner for {bus_name}: {error:#}");
                self.schedule_owner_retry(bus_name).await;
            }
        }
    }

    fn reconcile_known_owner<'a>(
        self: &'a Arc<Self>,
        bus_name: &'a str,
        owner: Option<String>,
    ) -> BoxFuture<'a, ()> {
        Box::pin(async move {
            let _reconciliation = self.owner_reconciliation.lock().await;
            let mut owners = self.owners.lock().await;
            if owners
                .get(bus_name)
                .is_some_and(|entry| owner_state_is_current(entry, owner.as_deref()))
            {
                return;
            }
            if owner.is_none() && !owners.contains_key(bus_name) {
                return;
            }

            let entry = owners
                .entry(bus_name.to_owned())
                .or_insert_with(|| PlayerOwner {
                    order: self.next_owner_order.fetch_add(1, Ordering::Relaxed),
                    unique_name: None,
                    generation: 0,
                    watcher: None,
                    restart_delay: WATCHER_RESTART_DELAY,
                });
            if entry.unique_name.as_deref() != owner.as_deref() {
                entry.restart_delay = WATCHER_RESTART_DELAY;
            }
            entry.generation = entry.generation.wrapping_add(1);
            let generation = entry.generation;
            if let Some(watcher) = entry.watcher.take() {
                watcher.handle.abort();
            }
            entry.unique_name = owner.clone();
            self.players
                .write()
                .await
                .retain(|player| player.bus_name != bus_name);

            let Some(unique_name) = owner else {
                return;
            };
            drop(owners);

            let registry = Arc::clone(self);
            let watched_bus_name = bus_name.to_owned();
            let watched_owner = unique_name.clone();
            let watcher_id = self.next_watcher_id.fetch_add(1, Ordering::Relaxed);
            let (start_tx, start_rx) = oneshot::channel();
            let handle = tokio::spawn(async move {
                if start_rx.await.is_err() {
                    return;
                }
                let result = registry
                    .watch_player(&watched_bus_name, &watched_owner, generation)
                    .await;
                if let Err(error) = result {
                    eprintln!(
                        "MPRIS watcher stopped for {watched_bus_name} ({watched_owner}): {error:#}"
                    );
                }
                registry
                    .recover_watcher(&watched_bus_name, &watched_owner, generation, watcher_id)
                    .await;
            });

            let mut owners = self.owners.lock().await;
            match owners.get_mut(bus_name) {
                Some(entry)
                    if entry.generation == generation
                        && entry.unique_name.as_deref() == Some(unique_name.as_str()) =>
                {
                    entry.watcher = Some(PlayerWatcher {
                        id: watcher_id,
                        handle,
                    });
                    let _ = start_tx.send(());
                }
                _ => handle.abort(),
            }
        })
    }

    async fn current_owner(&self, bus_name: &str) -> Result<Option<String>> {
        let name = BusName::try_from(bus_name).context("validate D-Bus bus name")?;
        let dbus = fdo::DBusProxy::new(&self.connection).await?;
        match dbus.get_name_owner(name).await {
            Ok(owner) => Ok(Some(owner.as_str().to_owned())),
            Err(fdo::Error::NameHasNoOwner(_)) => Ok(None),
            Err(error) => Err(error.into()),
        }
    }

    async fn schedule_owner_retry(self: &Arc<Self>, bus_name: &str) {
        let bus_name = bus_name.to_owned();
        if !self.owner_retries.lock().await.insert(bus_name.clone()) {
            return;
        }

        let registry = Arc::clone(self);
        tokio::spawn(async move {
            let mut delay = WATCHER_RESTART_DELAY;
            loop {
                tokio::time::sleep(delay).await;
                match registry.current_owner(&bus_name).await {
                    Ok(owner) => {
                        registry.reconcile_known_owner(&bus_name, owner).await;
                        registry.owner_retries.lock().await.remove(&bus_name);
                        return;
                    }
                    Err(error) => {
                        eprintln!("failed to retry D-Bus owner query for {bus_name}: {error:#}");
                        delay = (delay * 2).min(OWNER_RETRY_MAX_DELAY);
                    }
                }
            }
        });
    }

    async fn recover_watcher(
        self: &Arc<Self>,
        bus_name: &str,
        unique_name: &str,
        generation: u64,
        watcher_id: u64,
    ) {
        let mut owners = self.owners.lock().await;
        let Some(entry) = owners.get_mut(bus_name) else {
            return;
        };
        if !watcher_is_current(entry, unique_name, generation, watcher_id) {
            return;
        }

        entry.watcher.take();
        entry.generation = entry.generation.wrapping_add(1);
        let restart_delay = entry.restart_delay;
        entry.restart_delay = next_retry_delay(restart_delay);
        self.players
            .write()
            .await
            .retain(|player| player.bus_name != bus_name);
        drop(owners);

        tokio::time::sleep(restart_delay).await;
        self.reconcile_owner(bus_name).await;
    }

    async fn publish_initial_state(
        &self,
        bus_name: &str,
        unique_name: &str,
        generation: u64,
        initial: PlayerState,
    ) -> bool {
        let mut owners = self.owners.lock().await;
        let Some(entry) = owners.get_mut(bus_name) else {
            return false;
        };
        if entry.generation != generation || entry.unique_name.as_deref() != Some(unique_name) {
            return false;
        }
        entry.restart_delay = WATCHER_RESTART_DELAY;
        let mut players = self.players.write().await;
        players.retain(|state| state.bus_name != bus_name);
        players.push(initial);
        true
    }

    fn spawn_position_reconciliation(self: &Arc<Self>) {
        let registry = Arc::clone(self);
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(POSITION_RECONCILIATION_INTERVAL);
            interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            interval.tick().await;
            loop {
                interval.tick().await;
                registry.reconcile_playing_positions().await;
            }
        });
    }

    async fn reconcile_playing_positions(&self) {
        let targets = {
            let owners = self.owners.lock().await;
            let players = self.players.read().await;
            position_reconciliation_targets(&players, &owners)
        };
        for target in targets {
            let position = match Proxy::new(
                &self.connection,
                target.unique_name.as_str(),
                MPRIS_PATH,
                PLAYER_IFACE,
            )
            .await
            {
                Ok(player) => player.get_property::<i64>("Position").await.ok(),
                Err(_) => None,
            };
            let Some(position) = position else {
                continue;
            };
            self.apply_reconciled_position(&target, position, Instant::now())
                .await;
        }
    }

    async fn apply_reconciled_position(
        &self,
        target: &PositionReconciliationTarget,
        position: i64,
        now: Instant,
    ) {
        let owners = self.owners.lock().await;
        if !reconciliation_target_is_current(target, &owners) {
            return;
        }
        let mut players = self.players.write().await;
        if let Some(player) = players.iter_mut().find(|player| {
            player.bus_name == target.bus_name && player.playback_status == PlaybackStatus::Playing
        }) {
            player.base_position_us = position.max(0);
            player.position_updated_at = now;
        }
    }

    async fn watch_player(&self, bus_name: &str, unique_name: &str, generation: u64) -> Result<()> {
        let properties =
            Proxy::new(&self.connection, unique_name, MPRIS_PATH, PROPERTIES_IFACE).await?;
        let root = Proxy::new(&self.connection, unique_name, MPRIS_PATH, ROOT_IFACE).await?;
        let player = Proxy::new(&self.connection, unique_name, MPRIS_PATH, PLAYER_IFACE).await?;

        let mut property_stream = properties.receive_signal("PropertiesChanged").await?;
        let mut seeked_stream = player.receive_signal("Seeked").await?;
        let initial = load_player(&properties, bus_name).await?;
        if !self
            .publish_initial_state(bus_name, unique_name, generation, initial)
            .await
        {
            return Ok(());
        }

        loop {
            tokio::select! {
                signal = property_stream.next() => {
                    let Some(signal) = signal else {
                        eprintln!("MPRIS PropertiesChanged stream ended for {bus_name} ({unique_name})");
                        return Ok(());
                    };
                    let (interface, mut changed, invalidated): (String, HashMap<String, OwnedValue>, Vec<String>) =
                        match signal.body().deserialize() {
                            Ok(body) => body,
                            Err(error) => {
                                eprintln!("invalid MPRIS PropertiesChanged signal for {bus_name}: {error}");
                                continue;
                            }
                        };
                    let proxy = if interface == ROOT_IFACE { &root } else { &player };
                    for property in invalidated {
                        if is_tracked_property(&interface, &property) {
                            match proxy.get_property::<OwnedValue>(&property).await {
                                Ok(value) => { changed.insert(property, value); }
                                Err(error) => eprintln!(
                                    "failed to refresh invalidated MPRIS property {property} for {bus_name}: {error}"
                                ),
                            }
                        }
                    }
                    self.apply_properties(bus_name, unique_name, generation, &interface, &changed).await;
                }
                signal = seeked_stream.next() => {
                    let Some(signal) = signal else {
                        eprintln!("MPRIS Seeked stream ended for {bus_name} ({unique_name})");
                        return Ok(());
                    };
                    let (position,): (i64,) = match signal.body().deserialize() {
                        Ok(body) => body,
                        Err(error) => {
                            eprintln!("invalid MPRIS Seeked signal for {bus_name}: {error}");
                            continue;
                        }
                    };
                    let owners = self.owners.lock().await;
                    if !owners.get(bus_name).is_some_and(|entry| {
                        entry.generation == generation
                            && entry.unique_name.as_deref() == Some(unique_name)
                    }) {
                        return Ok(());
                    }
                    let mut players = self.players.write().await;
                    if let Some(state) = players.iter_mut().find(|state| state.bus_name == bus_name) {
                        state.base_position_us = position.max(0);
                        state.position_updated_at = Instant::now();
                    }
                }
            }
        }
    }

    async fn apply_properties(
        &self,
        bus_name: &str,
        unique_name: &str,
        generation: u64,
        interface: &str,
        changed: &HashMap<String, OwnedValue>,
    ) {
        let track_changed = if interface == PLAYER_IFACE {
            let players = self.players.read().await;
            players
                .iter()
                .find(|state| state.bus_name == bus_name)
                .and_then(|state| {
                    changed
                        .get("Metadata")
                        .and_then(metadata_from_value)
                        .map(|track| track_identity_changed(&state.track, &track))
                })
                .unwrap_or(false)
        } else {
            false
        };
        let refreshed_position = if track_changed && !changed.contains_key("Position") {
            match Proxy::new(&self.connection, unique_name, MPRIS_PATH, PLAYER_IFACE).await {
                Ok(player) => player.get_property::<i64>("Position").await.ok(),
                Err(_) => None,
            }
        } else {
            None
        };
        let owners = self.owners.lock().await;
        if !owners.get(bus_name).is_some_and(|entry| {
            entry.generation == generation && entry.unique_name.as_deref() == Some(unique_name)
        }) {
            return;
        }
        let mut players = self.players.write().await;
        let Some(player) = players.iter_mut().find(|state| state.bus_name == bus_name) else {
            return;
        };
        apply_properties_to_state(
            player,
            interface,
            changed,
            refreshed_position,
            Instant::now(),
        );
    }

    pub async fn snapshot(&self) -> Vec<PlayerState> {
        let owners = self.owners.lock().await;
        let mut players = self.players.read().await.clone();
        sort_players_by_owner_order(&mut players, &owners);
        players
    }

    pub async fn control(&self, bus_name: &str, action: &str) -> bool {
        let unique_name = {
            let owners = self.owners.lock().await;
            let Some(owner) = owners.get(bus_name) else {
                return false;
            };
            let Some(unique_name) = owner.unique_name.clone() else {
                return false;
            };
            unique_name
        };
        let (interface, method) = match action {
            "play" => (PLAYER_IFACE, "Play"),
            "pause" => (PLAYER_IFACE, "Pause"),
            "play_pause" => (PLAYER_IFACE, "PlayPause"),
            "stop" => (PLAYER_IFACE, "Stop"),
            "next" => (PLAYER_IFACE, "Next"),
            "previous" => (PLAYER_IFACE, "Previous"),
            "raise" => (ROOT_IFACE, "Raise"),
            "quit" => (ROOT_IFACE, "Quit"),
            _ => return false,
        };
        let Ok(proxy) = Proxy::new(&self.connection, unique_name, MPRIS_PATH, interface).await
        else {
            return false;
        };
        match proxy.call_method(method, &()).await {
            Ok(_) => true,
            Err(error) => {
                eprintln!("MPRIS {method} failed for {bus_name}: {error}");
                false
            }
        }
    }
}

#[derive(Debug, Eq, PartialEq)]
struct PositionReconciliationTarget {
    bus_name: String,
    unique_name: String,
    generation: u64,
}

fn position_reconciliation_targets(
    players: &[PlayerState],
    owners: &HashMap<String, PlayerOwner>,
) -> Vec<PositionReconciliationTarget> {
    players
        .iter()
        .filter(|player| player.playback_status == PlaybackStatus::Playing)
        .filter_map(|player| {
            let owner = owners.get(&player.bus_name)?;
            Some(PositionReconciliationTarget {
                bus_name: player.bus_name.clone(),
                unique_name: owner.unique_name.clone()?,
                generation: owner.generation,
            })
        })
        .collect()
}

fn reconciliation_target_is_current(
    target: &PositionReconciliationTarget,
    owners: &HashMap<String, PlayerOwner>,
) -> bool {
    owners.get(&target.bus_name).is_some_and(|owner| {
        owner.generation == target.generation
            && owner.unique_name.as_deref() == Some(target.unique_name.as_str())
    })
}

fn sort_players_by_owner_order(players: &mut [PlayerState], owners: &HashMap<String, PlayerOwner>) {
    players.sort_by_key(|player| {
        owners
            .get(&player.bus_name)
            .map(|owner| owner.order)
            .unwrap_or(u64::MAX)
    });
}

fn watcher_is_current(
    entry: &PlayerOwner,
    unique_name: &str,
    generation: u64,
    watcher_id: u64,
) -> bool {
    watcher_identity_is_current(
        entry.unique_name.as_deref(),
        entry.generation,
        entry.watcher.as_ref().map(|watcher| watcher.id),
        unique_name,
        generation,
        watcher_id,
    )
}

fn watcher_identity_is_current(
    current_owner: Option<&str>,
    current_generation: u64,
    current_watcher_id: Option<u64>,
    watched_owner: &str,
    watched_generation: u64,
    watcher_id: u64,
) -> bool {
    current_generation == watched_generation
        && current_owner == Some(watched_owner)
        && current_watcher_id == Some(watcher_id)
}

fn owner_state_is_current(entry: &PlayerOwner, owner: Option<&str>) -> bool {
    entry.unique_name.as_deref() == owner
        && match owner {
            Some(_) => entry.watcher.is_some(),
            None => entry.watcher.is_none(),
        }
}

fn next_retry_delay(delay: Duration) -> Duration {
    (delay * 2).min(OWNER_RETRY_MAX_DELAY)
}

async fn load_player(properties: &Proxy<'_>, bus_name: &str) -> Result<PlayerState> {
    let root: HashMap<String, OwnedValue> = properties.call("GetAll", &(ROOT_IFACE)).await?;
    let player: HashMap<String, OwnedValue> = properties.call("GetAll", &(PLAYER_IFACE)).await?;
    Ok(PlayerState {
        bus_name: bus_name.to_owned(),
        identity: value_string(root.get("Identity")).unwrap_or_else(|| "Unknown".to_owned()),
        track: player
            .get("Metadata")
            .and_then(metadata_from_value)
            .unwrap_or_default(),
        playback_status: value_string(player.get("PlaybackStatus"))
            .map(|value| PlaybackStatus::parse(&value))
            .unwrap_or_default(),
        rate: value_f64(player.get("Rate")).unwrap_or(1.0),
        base_position_us: value_i64(player.get("Position")).unwrap_or(0).max(0),
        position_updated_at: Instant::now(),
    })
}

fn apply_properties_to_state(
    player: &mut PlayerState,
    interface: &str,
    changed: &HashMap<String, OwnedValue>,
    refreshed_position: Option<i64>,
    now: Instant,
) {
    if interface == ROOT_IFACE {
        if let Some(identity) = value_string(changed.get("Identity")) {
            player.identity = identity;
        }
        return;
    }
    if interface != PLAYER_IFACE {
        return;
    }

    let previous_status = player.playback_status;
    player.rebase(now);
    if let Some(status) = value_string(changed.get("PlaybackStatus")) {
        player.playback_status = PlaybackStatus::parse(&status);
        if previous_status == PlaybackStatus::Stopped
            && player.playback_status == PlaybackStatus::Playing
            && !changed.contains_key("Position")
        {
            player.base_position_us = 0;
        }
    }
    if let Some(rate) = value_f64(changed.get("Rate")) {
        player.rate = rate;
    }
    if let Some(metadata) = changed.get("Metadata").and_then(metadata_from_value) {
        let track_changed = track_identity_changed(&player.track, &metadata);
        player.track = metadata;
        if track_changed {
            player.base_position_us = refreshed_position.unwrap_or(0).max(0);
        }
    }
    if let Some(position) = value_i64(changed.get("Position")) {
        player.base_position_us = position.max(0);
    }
    player.position_updated_at = now;
}

fn track_identity_changed(previous: &Track, next: &Track) -> bool {
    (!previous.track_id.is_empty()
        && !next.track_id.is_empty()
        && previous.track_id != next.track_id)
        || previous.title != next.title
        || previous.artists != next.artists
        || previous.album != next.album
}

fn metadata_from_value(value: &OwnedValue) -> Option<Track> {
    let metadata: HashMap<String, OwnedValue> = value.try_clone().ok()?.try_into().ok()?;
    Some(Track {
        title: value_string(metadata.get("xesam:title")).unwrap_or_default(),
        artists: value_strings(metadata.get("xesam:artist")).unwrap_or_default(),
        album: value_string(metadata.get("xesam:album")).unwrap_or_default(),
        duration_us: value_i64(metadata.get("mpris:length")).unwrap_or(0).max(0),
        track_id: value_object_path(metadata.get("mpris:trackid")).unwrap_or_default(),
        url: value_string(metadata.get("xesam:url")).unwrap_or_default(),
    })
}

fn value_string(value: Option<&OwnedValue>) -> Option<String> {
    value?.try_clone().ok()?.try_into().ok()
}

fn value_strings(value: Option<&OwnedValue>) -> Option<Vec<String>> {
    let value = value?;
    value
        .try_clone()
        .ok()?
        .try_into()
        .ok()
        .or_else(|| value_string(Some(value)).map(|artist| vec![artist]))
}

fn value_object_path(value: Option<&OwnedValue>) -> Option<String> {
    let path: OwnedObjectPath = value?.try_clone().ok()?.try_into().ok()?;
    Some(path.as_str().to_owned())
}

fn value_i64(value: Option<&OwnedValue>) -> Option<i64> {
    let value = value?;
    i64::try_from(value)
        .ok()
        .or_else(|| {
            u64::try_from(value)
                .ok()
                .and_then(|number| number.try_into().ok())
        })
        .or_else(|| i32::try_from(value).ok().map(i64::from))
        .or_else(|| u32::try_from(value).ok().map(i64::from))
        .or_else(|| i16::try_from(value).ok().map(i64::from))
        .or_else(|| u16::try_from(value).ok().map(i64::from))
        .or_else(|| u8::try_from(value).ok().map(i64::from))
}

fn value_f64(value: Option<&OwnedValue>) -> Option<f64> {
    value?.try_into().ok()
}

fn is_tracked_property(interface: &str, property: &str) -> bool {
    match interface {
        ROOT_IFACE => property == "Identity",
        PLAYER_IFACE => matches!(
            property,
            "Metadata" | "PlaybackStatus" | "Position" | "Rate"
        ),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, time::Instant};

    use zvariant::{ObjectPath, OwnedValue, Str, Value};

    use super::{
        PLAYER_IFACE, PlayerOwner, PositionReconciliationTarget, apply_properties_to_state,
        metadata_from_value, next_retry_delay, position_reconciliation_targets,
        reconciliation_target_is_current, sort_players_by_owner_order, value_i64,
        watcher_identity_is_current,
    };
    use crate::model::{PlaybackStatus, PlayerState, Track};

    fn state(status: PlaybackStatus, position: i64) -> PlayerState {
        PlayerState {
            bus_name: "org.mpris.MediaPlayer2.test".into(),
            identity: "Test".into(),
            track: Track::default(),
            playback_status: status,
            rate: 1.0,
            base_position_us: position,
            position_updated_at: Instant::now(),
        }
    }

    fn owner(order: u64, unique_name: &str, generation: u64) -> PlayerOwner {
        PlayerOwner {
            order,
            unique_name: Some(unique_name.into()),
            generation,
            watcher: None,
            restart_delay: std::time::Duration::from_secs(1),
        }
    }

    fn metadata_value(entries: HashMap<String, OwnedValue>) -> OwnedValue {
        OwnedValue::try_from(Value::from(entries)).unwrap()
    }

    #[test]
    fn stopped_to_playing_without_position_restarts_at_zero() {
        let mut player = state(PlaybackStatus::Stopped, 9_000_000);
        let changed = HashMap::from([(
            "PlaybackStatus".into(),
            OwnedValue::from(Str::from_static("Playing")),
        )]);

        apply_properties_to_state(&mut player, PLAYER_IFACE, &changed, None, Instant::now());

        assert_eq!(player.playback_status, PlaybackStatus::Playing);
        assert_eq!(player.base_position_us, 0);
    }

    #[test]
    fn stopped_to_playing_respects_explicit_position() {
        let mut player = state(PlaybackStatus::Stopped, 9_000_000);
        let changed = HashMap::from([
            (
                "PlaybackStatus".into(),
                OwnedValue::from(Str::from_static("Playing")),
            ),
            ("Position".into(), OwnedValue::from(2_000_000_i64)),
        ]);

        apply_properties_to_state(&mut player, PLAYER_IFACE, &changed, None, Instant::now());

        assert_eq!(player.base_position_us, 2_000_000);
    }

    #[test]
    fn metadata_refresh_for_same_track_keeps_position() {
        let mut player = state(PlaybackStatus::Playing, 9_000_000);
        player.track = Track {
            title: "Song".into(),
            artists: vec!["Artist".into()],
            album: "Album".into(),
            track_id: "/track/1".into(),
            ..Track::default()
        };
        let metadata = metadata_value(HashMap::from([
            (
                "xesam:title".into(),
                OwnedValue::from(Str::from_static("Song")),
            ),
            (
                "xesam:artist".into(),
                OwnedValue::try_from(Value::from(vec!["Artist"])).unwrap(),
            ),
            (
                "xesam:album".into(),
                OwnedValue::from(Str::from_static("Album")),
            ),
            (
                "mpris:trackid".into(),
                OwnedValue::from(ObjectPath::try_from("/track/1").unwrap()),
            ),
        ]));

        apply_properties_to_state(
            &mut player,
            PLAYER_IFACE,
            &HashMap::from([("Metadata".into(), metadata)]),
            None,
            Instant::now(),
        );

        assert!(player.base_position_us >= 9_000_000);
    }

    #[test]
    fn new_track_uses_refreshed_position() {
        let mut player = state(PlaybackStatus::Playing, 9_000_000);
        player.track.track_id = "/track/1".into();
        let metadata = metadata_value(HashMap::from([(
            "mpris:trackid".into(),
            OwnedValue::from(ObjectPath::try_from("/track/2").unwrap()),
        )]));

        apply_properties_to_state(
            &mut player,
            PLAYER_IFACE,
            &HashMap::from([("Metadata".into(), metadata)]),
            Some(750_000),
            Instant::now(),
        );

        assert_eq!(player.base_position_us, 750_000);
        assert_eq!(player.track.track_id, "/track/2");
    }

    #[test]
    fn reused_track_id_with_new_title_is_still_a_track_change() {
        let mut player = state(PlaybackStatus::Playing, 9_000_000);
        player.track.track_id = "/track/fixed".into();
        player.track.title = "Old Song".into();
        let metadata = metadata_value(HashMap::from([
            (
                "mpris:trackid".into(),
                OwnedValue::from(ObjectPath::try_from("/track/fixed").unwrap()),
            ),
            (
                "xesam:title".into(),
                OwnedValue::from(Str::from_static("New Song")),
            ),
        ]));

        apply_properties_to_state(
            &mut player,
            PLAYER_IFACE,
            &HashMap::from([("Metadata".into(), metadata)]),
            Some(500_000),
            Instant::now(),
        );

        assert_eq!(player.base_position_us, 500_000);
        assert_eq!(player.track.title, "New Song");
    }

    #[test]
    fn reused_track_id_with_new_title_is_a_track_change() {
        let previous = Track {
            title: "Old Song".into(),
            track_id: "/track/fixed".into(),
            ..Track::default()
        };
        let next = Track {
            title: "New Song".into(),
            track_id: "/track/fixed".into(),
            ..Track::default()
        };

        assert!(super::track_identity_changed(&previous, &next));
    }

    #[test]
    fn metadata_decodes_object_path_artist_array_and_unsigned_length() {
        let path = ObjectPath::try_from("/org/mpris/MediaPlayer2/Track/42").unwrap();
        let metadata = metadata_value(HashMap::from([
            (
                "xesam:title".into(),
                OwnedValue::from(Str::from_static("Song")),
            ),
            (
                "xesam:artist".into(),
                OwnedValue::try_from(Value::from(vec!["One", "Two"])).unwrap(),
            ),
            ("mpris:length".into(), OwnedValue::from(4_000_000_u64)),
            ("mpris:trackid".into(), OwnedValue::from(path)),
        ]));

        let track = metadata_from_value(&metadata).unwrap();

        assert_eq!(track.title, "Song");
        assert_eq!(track.artists, ["One", "Two"]);
        assert_eq!(track.duration_us, 4_000_000);
        assert_eq!(track.track_id, "/org/mpris/MediaPlayer2/Track/42");
    }

    #[test]
    fn metadata_accepts_single_artist_and_signed_length() {
        let metadata = metadata_value(HashMap::from([
            (
                "xesam:artist".into(),
                OwnedValue::from(Str::from_static("Solo")),
            ),
            ("mpris:length".into(), OwnedValue::from(123_i32)),
        ]));

        let track = metadata_from_value(&metadata).unwrap();

        assert_eq!(track.artists, ["Solo"]);
        assert_eq!(track.duration_us, 123);
    }

    #[test]
    fn integer_conversion_rejects_u64_overflow() {
        let too_large = OwnedValue::from(i64::MAX as u64 + 1);
        assert_eq!(value_i64(Some(&too_large)), None);
    }

    #[test]
    fn watcher_recovery_requires_exact_owner_generation_and_handle() {
        assert!(watcher_identity_is_current(
            Some(":1.42"),
            7,
            Some(11),
            ":1.42",
            7,
            11,
        ));
        assert!(!watcher_identity_is_current(
            Some(":1.43"),
            7,
            Some(11),
            ":1.42",
            7,
            11,
        ));
        assert!(!watcher_identity_is_current(
            Some(":1.42"),
            8,
            Some(11),
            ":1.42",
            7,
            11,
        ));
        assert!(!watcher_identity_is_current(
            Some(":1.42"),
            7,
            Some(12),
            ":1.42",
            7,
            11,
        ));
    }

    #[test]
    fn watcher_retry_delay_has_a_thirty_second_cap() {
        assert_eq!(
            next_retry_delay(std::time::Duration::from_secs(1)),
            std::time::Duration::from_secs(2),
        );
        assert_eq!(
            next_retry_delay(std::time::Duration::from_secs(20)),
            std::time::Duration::from_secs(30),
        );
        assert_eq!(
            next_retry_delay(std::time::Duration::from_secs(30)),
            std::time::Duration::from_secs(30),
        );
    }

    #[test]
    fn snapshot_order_is_registration_order_not_publish_order() {
        let mut later = state(PlaybackStatus::Paused, 0);
        later.bus_name = "later".into();
        let mut earlier = state(PlaybackStatus::Playing, 0);
        earlier.bus_name = "earlier".into();
        let mut players = vec![later, earlier];
        let owners = HashMap::from([
            ("earlier".into(), owner(3, ":1.3", 1)),
            ("later".into(), owner(4, ":1.4", 1)),
        ]);

        sort_players_by_owner_order(&mut players, &owners);

        assert_eq!(players[0].bus_name, "earlier");
        assert_eq!(players[1].bus_name, "later");
    }

    #[test]
    fn position_reconciliation_only_targets_playing_current_owners() {
        let mut playing = state(PlaybackStatus::Playing, 0);
        playing.bus_name = "playing".into();
        let mut paused = state(PlaybackStatus::Paused, 0);
        paused.bus_name = "paused".into();
        let owners = HashMap::from([
            ("playing".into(), owner(0, ":1.1", 7)),
            ("paused".into(), owner(1, ":1.2", 8)),
        ]);

        let targets = position_reconciliation_targets(&[playing, paused], &owners);

        assert_eq!(
            targets,
            vec![PositionReconciliationTarget {
                bus_name: "playing".into(),
                unique_name: ":1.1".into(),
                generation: 7,
            }]
        );
        assert!(reconciliation_target_is_current(&targets[0], &owners));
        let stale = PositionReconciliationTarget {
            generation: 6,
            ..targets.into_iter().next().unwrap()
        };
        assert!(!reconciliation_target_is_current(&stale, &owners));
    }
}
