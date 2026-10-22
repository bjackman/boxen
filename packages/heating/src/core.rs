//! The control loop, with no I/O and no clock: callers pass in the time and
//! carry out the returned actions.

use std::collections::BTreeMap;
use std::time::Duration;

use log::{info, warn};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::config::{Config, Limits, Params, RoomConfig};

/// Monotonic time since the controller started.
pub type Time = Duration;

/// Wall-clock time since the Unix epoch.
pub type WallTime = Duration;

/// Setpoints closer together than this are the same setpoint. The TRVZB works
/// in 0.5 °C steps.
const TOLERANCE: f64 = 0.1;

#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    Subscribe(Vec<String>),
    Publish { topic: String, payload: String },
    Persist(Persisted),
}

/// What survives a restart: the settings made in the web UI.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Persisted {
    #[serde(default)]
    pub targets: BTreeMap<String, f64>,
    #[serde(default, deserialize_with = "saved_params")]
    pub params: Option<Params>,
    /// Each room's learned offset, so that it isn't relearned after a restart.
    #[serde(default)]
    pub offsets: BTreeMap<String, f64>,
}

fn saved_params<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Params>, D::Error> {
    Option::<Value>::deserialize(deserializer)?
        .map(|saved| Params::from_saved(saved).map_err(serde::de::Error::custom))
        .transpose()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status {
    Disconnected,
    ValveOffline,
    WaitingForValve,
    ValveNotHeating,
    SensorOffline,
    WaitingForSensor,
    SensorStale,
    Active,
}

impl Status {
    pub const ALL: [Status; 8] = [
        Status::Disconnected,
        Status::ValveOffline,
        Status::WaitingForValve,
        Status::ValveNotHeating,
        Status::SensorOffline,
        Status::WaitingForSensor,
        Status::SensorStale,
        Status::Active,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            Status::Disconnected => "disconnected",
            Status::ValveOffline => "valve_offline",
            Status::WaitingForValve => "waiting_for_valve",
            Status::ValveNotHeating => "valve_not_heating",
            Status::SensorOffline => "sensor_offline",
            Status::WaitingForSensor => "waiting_for_sensor",
            Status::SensorStale => "sensor_stale",
            Status::Active => "active",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Snapshot {
    pub connected: bool,
    pub params: Params,
    pub limits: Limits,
    pub rooms: Vec<RoomSnapshot>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RoomSnapshot {
    pub name: String,
    pub status: Status,
    pub target: f64,
    pub override_delta: Option<f64>,
    pub override_remaining: Option<Duration>,
    pub effective_target: f64,
    pub temperature: Option<f64>,
    pub temperature_age: Option<Duration>,
    pub desired_setpoint: Option<f64>,
    pub reported_setpoint: Option<f64>,
    pub valve_temperature: Option<f64>,
    pub valve_mode: Option<String>,
    pub error: Option<f64>,
    pub proportional: Option<f64>,
    pub offset: f64,
    pub computed_setpoint: Option<f64>,
    pub write_pending: bool,
    pub writes: u64,
    pub retries: u64,
    pub knob_turns: u64,
}

#[derive(Clone, Copy, Debug)]
struct Reading {
    temperature: f64,
    received: Time,
    /// How old it already was when it arrived: zigbee2mqtt can deliver a
    /// retained or replayed message long after the sensor sent it.
    age_when_received: Duration,
}

impl Reading {
    fn age(&self, now: Time) -> Duration {
        self.age_when_received + now.saturating_sub(self.received)
    }

    fn stale_at(&self, stale_after: Duration) -> Option<Time> {
        stale_after
            .checked_sub(self.age_when_received)
            .map(|left| self.received + left)
    }
}

#[derive(Clone, Copy, Debug)]
struct Override {
    delta: f64,
    until: Time,
}

#[derive(Clone, Copy, Debug)]
struct PendingWrite {
    value: f64,
    previous: f64,
    sent_at: Time,
}

#[derive(Clone, Debug)]
struct Room {
    config: RoomConfig,
    target: f64,
    knob: Option<Override>,
    sensor_online: bool,
    reading: Option<Reading>,
    valve_online: bool,
    reported_setpoint: Option<f64>,
    valve_mode: Option<String>,
    valve_temperature: Option<f64>,
    /// The setpoint the valve should have: what we last wrote, or what it was
    /// turned to.
    desired: Option<f64>,
    pending: Option<PendingWrite>,
    last_change: Option<Time>,
    /// The integral term: what the setpoint needs on top of target and
    /// proportional term to hold the room at target. It mostly makes up for
    /// the valve's sensor sitting in the radiator's warmth.
    offset: f64,
    last_integration: Option<Time>,
    writes: u64,
    retries: u64,
    knob_turns: u64,
}

pub struct Controller {
    base_topic: String,
    limits: Limits,
    params: Params,
    connected: bool,
    rooms: Vec<Room>,
}

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < TOLERANCE
}

fn floor_half(x: f64) -> f64 {
    (x * 2.0).floor() / 2.0
}

fn ceil_half(x: f64) -> f64 {
    (x * 2.0).ceil() / 2.0
}

fn round_half(x: f64) -> f64 {
    (x * 2.0).round() / 2.0
}

fn number(state: &Map<String, Value>, key: &str) -> Option<f64> {
    state.get(key)?.as_f64().filter(|n| n.is_finite())
}

/// How long ago zigbee2mqtt last heard from the device, from the epoch
/// milliseconds it adds as last_seen. Zero without it, or if it's in the future.
fn last_seen_age(state: &Map<String, Value>, wall: WallTime) -> Duration {
    state
        .get("last_seen")
        .and_then(Value::as_u64)
        .map_or(Duration::ZERO, |ms| {
            wall.saturating_sub(Duration::from_millis(ms))
        })
}

fn parse_state(payload: &[u8]) -> Option<Map<String, Value>> {
    match serde_json::from_slice(payload) {
        Ok(Value::Object(state)) => Some(state),
        _ => None,
    }
}

/// zigbee2mqtt publishes {"state":"online"}, or plain "online" in its legacy
/// availability mode.
fn parse_availability(payload: &[u8]) -> Option<bool> {
    let state = match serde_json::from_slice::<Value>(payload) {
        Ok(Value::Object(object)) => object.get("state")?.as_str()?.to_owned(),
        Ok(Value::String(state)) => state,
        _ => std::str::from_utf8(payload).ok()?.trim().to_owned(),
    };
    match state.as_str() {
        "online" => Some(true),
        "offline" => Some(false),
        _ => None,
    }
}

impl Room {
    fn effective_target(&self) -> f64 {
        self.target + self.knob.map_or(0.0, |k| k.delta)
    }

    fn status(&self, now: Time, connected: bool, limits: &Limits) -> Status {
        if !connected {
            return Status::Disconnected;
        }
        if !self.valve_online {
            return Status::ValveOffline;
        }
        if self.reported_setpoint.is_none() || self.desired.is_none() {
            return Status::WaitingForValve;
        }
        match self.valve_mode.as_deref() {
            None => return Status::WaitingForValve,
            Some("heat") => {}
            Some(_) => return Status::ValveNotHeating,
        }
        if !self.sensor_online {
            return Status::SensorOffline;
        }
        match self.reading {
            None => Status::WaitingForSensor,
            Some(r) if r.age(now) >= limits.sensor_stale_after() => Status::SensorStale,
            Some(_) => Status::Active,
        }
    }

    fn set_action(&self, base_topic: &str, value: f64) -> Action {
        Action::Publish {
            topic: format!("{base_topic}/{}/set", self.config.valve),
            payload: serde_json::json!({ "occupied_heating_setpoint": value }).to_string(),
        }
    }

    fn on_valve_state(
        &mut self,
        now: Time,
        state: &Map<String, Value>,
        params: &Params,
        limits: &Limits,
    ) {
        if let Some(mode) = state.get("system_mode").and_then(Value::as_str) {
            self.valve_mode = Some(mode.to_owned());
        }
        if let Some(temperature) = number(state, "local_temperature") {
            self.valve_temperature = Some(temperature);
        }
        let Some(setpoint) = number(state, "occupied_heating_setpoint") else {
            return;
        };
        self.reported_setpoint = Some(setpoint);

        let Some(desired) = self.desired else {
            info!(
                "{}: valve setpoint is {setpoint}, starting from there",
                self.config.name
            );
            self.desired = Some(setpoint);
            return;
        };

        // zigbee2mqtt repeats the whole cached state in every message, so the
        // setpoint shows up unchanged in most of them.
        if let Some(pending) = self.pending {
            if close(setpoint, pending.value) {
                self.pending = None;
            } else if !close(setpoint, pending.previous) {
                self.pending = None;
                self.knob_turned(now, setpoint, setpoint - pending.value, params, limits);
            }
            // Otherwise the write hasn't landed yet. It's retried after the
            // confirmation timeout.
        } else if !close(setpoint, desired) {
            self.knob_turned(now, setpoint, setpoint - desired, params, limits);
        }
    }

    fn knob_turned(
        &mut self,
        now: Time,
        setpoint: f64,
        delta: f64,
        params: &Params,
        limits: &Limits,
    ) {
        let total = (self.knob.map_or(0.0, |k| k.delta) + delta)
            .clamp(-limits.max_override, limits.max_override);
        info!(
            "{}: valve turned to {setpoint}, room target adjusted by {total:+}",
            self.config.name
        );
        self.desired = Some(setpoint);
        self.knob = (total.abs() >= TOLERANCE).then(|| Override {
            delta: total,
            until: now + params.override_duration(),
        });
        // Let the valve act on the new setpoint before stepping away from it.
        self.last_change = Some(now);
        self.knob_turns += 1;
    }

    /// The room's error, the proportional term, and the setpoint the control
    /// law asks for now, if there's a reading to work from.
    fn law(&self, params: &Params, limits: &Limits) -> Option<(f64, f64, f64)> {
        let target = self.effective_target();
        let error = target - self.reading?.temperature;
        let proportional = params.kp * error;
        let setpoint = self.clamp_setpoint(target + proportional + self.offset, params, limits);
        Some((error, proportional, setpoint))
    }

    /// The lowest and highest setpoints allowed: the offset band, within the
    /// absolute limits, which win if the band falls outside them.
    fn setpoint_bounds(&self, params: &Params, limits: &Limits) -> (f64, f64) {
        let target = self.effective_target();
        let clamp = |x: f64| {
            x.max(ceil_half(limits.setpoint_min))
                .min(floor_half(limits.setpoint_max))
        };
        (
            clamp(ceil_half(target + params.min_offset)),
            clamp(floor_half(target + params.max_offset)),
        )
    }

    /// Whole and half degrees within the setpoint bounds.
    fn clamp_setpoint(&self, setpoint: f64, params: &Params, limits: &Limits) -> f64 {
        let (low, high) = self.setpoint_bounds(params, limits);
        round_half(setpoint).max(low).min(high)
    }

    /// Moves the learned offset once per step interval, while the room is
    /// outside the deadband but within the integration band, and the setpoint
    /// isn't already pinned at the limit the error pushes it towards. Returns
    /// whether it changed.
    fn integrate(&mut self, now: Time, params: &Params, limits: &Limits) -> bool {
        let Some(last) = self.last_integration else {
            self.last_integration = Some(now);
            return false;
        };
        if now < last + params.step_interval() {
            return false;
        }
        self.last_integration = Some(now);
        let Some((error, proportional, _)) = self.law(params, limits) else {
            return false;
        };
        if error.abs() <= params.deadband || error.abs() > params.integration_band {
            return false;
        }
        let unclamped = self.effective_target() + proportional + self.offset;
        let (low, high) = self.setpoint_bounds(params, limits);
        if (error > 0.0 && unclamped >= high) || (error < 0.0 && unclamped <= low) {
            return false;
        }
        let offset = (self.offset + params.ki * error).clamp(params.min_offset, params.max_offset);
        let changed = offset != self.offset;
        self.offset = offset;
        changed
    }

    /// Returns the setpoint write it makes, if any, and whether the learned
    /// offset changed.
    fn evaluate(
        &mut self,
        now: Time,
        connected: bool,
        params: &Params,
        limits: &Limits,
        base_topic: &str,
    ) -> (Option<Action>, bool) {
        if let Some(pending) = &mut self.pending {
            if connected
                && self.valve_online
                && now >= pending.sent_at + limits.write_confirm_timeout()
            {
                warn!(
                    "{}: valve hasn't confirmed setpoint {}, sending it again",
                    self.config.name, pending.value
                );
                pending.sent_at = now;
                self.retries += 1;
                let value = pending.value;
                return (Some(self.set_action(base_topic, value)), false);
            }
            return (None, false);
        }
        if self.status(now, connected, limits) != Status::Active {
            return (None, false);
        }
        let offset_changed = self.integrate(now, params, limits);
        if self
            .last_change
            .is_some_and(|last| now < last + params.step_interval())
        {
            return (None, offset_changed);
        }
        let (Some(desired), Some((error, proportional, next))) =
            (self.desired, self.law(params, limits))
        else {
            return (None, offset_changed);
        };
        if close(next, desired) {
            return (None, offset_changed);
        }
        info!(
            "{}: error {error:+.1}, proportional {proportional:+.1}, offset {:+.2}, setpoint {desired} -> {next}",
            self.config.name, self.offset
        );
        self.pending = Some(PendingWrite {
            value: next,
            previous: desired,
            sent_at: now,
        });
        self.desired = Some(next);
        self.last_change = Some(now);
        self.writes += 1;
        (Some(self.set_action(base_topic, next)), offset_changed)
    }

    fn deadlines(&self, params: &Params, limits: &Limits) -> impl Iterator<Item = Time> {
        [
            self.knob.map(|k| k.until),
            self.pending
                .map(|p| p.sent_at + limits.write_confirm_timeout()),
            self.reading
                .and_then(|r| r.stale_at(limits.sensor_stale_after())),
            self.last_change.map(|t| t + params.step_interval()),
            self.last_integration.map(|t| t + params.step_interval()),
        ]
        .into_iter()
        .flatten()
    }
}

impl Controller {
    pub fn new(config: &Config, persisted: &Persisted) -> Self {
        let params = match &persisted.params {
            Some(params) => match params.validate() {
                Ok(()) => params.clone(),
                Err(err) => {
                    warn!("ignoring saved params: {err:#}");
                    config.default_params.clone()
                }
            },
            None => config.default_params.clone(),
        };
        let limits = &config.limits;
        let rooms = config
            .rooms
            .iter()
            .map(|room| {
                let saved = persisted.targets.get(&room.name).copied();
                let target = match saved {
                    Some(t)
                        if t.is_finite()
                            && (limits.target_min..=limits.target_max).contains(&t) =>
                    {
                        t
                    }
                    Some(t) => {
                        warn!("{}: ignoring saved target {t}", room.name);
                        room.default_target
                    }
                    None => room.default_target,
                };
                let offset = match persisted.offsets.get(&room.name).copied() {
                    Some(o) if o.is_finite() => o.clamp(params.min_offset, params.max_offset),
                    _ => 0.0,
                };
                Room {
                    config: room.clone(),
                    target,
                    knob: None,
                    sensor_online: true,
                    reading: None,
                    valve_online: true,
                    reported_setpoint: None,
                    valve_mode: None,
                    valve_temperature: None,
                    desired: None,
                    pending: None,
                    last_change: None,
                    offset,
                    last_integration: None,
                    writes: 0,
                    retries: 0,
                    knob_turns: 0,
                }
            })
            .collect();
        Self {
            base_topic: config.mqtt.base_topic.clone(),
            limits: config.limits.clone(),
            params,
            connected: false,
            rooms,
        }
    }

    pub fn connected(&mut self, now: Time) -> Vec<Action> {
        self.connected = true;
        self.expire_overrides(now);
        let base = &self.base_topic;
        let mut topics = Vec::new();
        for room in &self.rooms {
            for device in [&room.config.sensor, &room.config.valve] {
                topics.push(format!("{base}/{device}"));
                topics.push(format!("{base}/{device}/availability"));
            }
        }
        let mut actions = vec![Action::Subscribe(topics)];
        // The valve's state isn't retained, and it may have changed while we
        // weren't listening.
        for room in &self.rooms {
            actions.push(Action::Publish {
                topic: format!("{base}/{}/get", room.config.valve),
                payload: serde_json::json!({
                    "occupied_heating_setpoint": "",
                    "system_mode": "",
                    "local_temperature": "",
                })
                .to_string(),
            });
        }
        actions.extend(self.evaluate(now));
        actions
    }

    pub fn disconnected(&mut self, now: Time) -> Vec<Action> {
        self.connected = false;
        self.expire_overrides(now);
        Vec::new()
    }

    /// `wall` is the current wall-clock time, for judging the age of what the
    /// message reports.
    pub fn message(
        &mut self,
        now: Time,
        wall: WallTime,
        topic: &str,
        payload: &[u8],
    ) -> Vec<Action> {
        self.expire_overrides(now);
        let device_topic = topic
            .strip_prefix(self.base_topic.as_str())
            .and_then(|rest| rest.strip_prefix('/'));
        if let Some(device_topic) = device_topic {
            let (device, is_availability) = match device_topic.strip_suffix("/availability") {
                Some(device) => (device, true),
                None => (device_topic, false),
            };
            for room in &mut self.rooms {
                if device == room.config.sensor {
                    if is_availability {
                        if let Some(online) = parse_availability(payload) {
                            room.sensor_online = online;
                        }
                    } else if let Some(state) = parse_state(payload)
                        && let Some(temperature) = number(&state, "temperature")
                    {
                        room.reading = Some(Reading {
                            temperature,
                            received: now,
                            age_when_received: last_seen_age(&state, wall),
                        });
                    }
                } else if device == room.config.valve {
                    if is_availability {
                        if let Some(online) = parse_availability(payload) {
                            room.valve_online = online;
                        }
                    } else if let Some(state) = parse_state(payload) {
                        room.on_valve_state(now, &state, &self.params, &self.limits);
                    }
                }
            }
        }
        self.evaluate(now)
    }

    pub fn tick(&mut self, now: Time) -> Vec<Action> {
        self.expire_overrides(now);
        self.evaluate(now)
    }

    pub fn set_target(
        &mut self,
        now: Time,
        room: &str,
        target: f64,
    ) -> Result<Vec<Action>, String> {
        let limits = &self.limits;
        if !target.is_finite() || !(limits.target_min..=limits.target_max).contains(&target) {
            return Err(format!(
                "target must be between {} and {} °C",
                limits.target_min, limits.target_max
            ));
        }
        let Some(r) = self.rooms.iter_mut().find(|r| r.config.name == room) else {
            return Err(format!("no room called {room:?}"));
        };
        info!("{room}: target set to {target}");
        r.target = target;
        r.knob = None;
        self.expire_overrides(now);
        let mut actions = vec![Action::Persist(self.persisted())];
        actions.extend(self.evaluate(now));
        Ok(actions)
    }

    pub fn set_params(&mut self, now: Time, params: Params) -> Result<Vec<Action>, String> {
        params.validate().map_err(|err| format!("{err:#}"))?;
        info!("params set to {params:?}");
        self.params = params;
        self.expire_overrides(now);
        let mut actions = vec![Action::Persist(self.persisted())];
        actions.extend(self.evaluate(now));
        Ok(actions)
    }

    /// The next time `tick` has something to do, if nothing else happens first.
    /// Always later than `now`, so that waiting for it can't spin.
    pub fn next_deadline(&self, now: Time) -> Option<Time> {
        self.rooms
            .iter()
            .flat_map(|room| room.deadlines(&self.params, &self.limits))
            .filter(|&deadline| deadline > now)
            .min()
    }

    pub fn snapshot(&self, now: Time) -> Snapshot {
        Snapshot {
            connected: self.connected,
            params: self.params.clone(),
            limits: self.limits.clone(),
            rooms: self
                .rooms
                .iter()
                .map(|room| {
                    let law = room.law(&self.params, &self.limits);
                    RoomSnapshot {
                        name: room.config.name.clone(),
                        status: room.status(now, self.connected, &self.limits),
                        target: room.target,
                        override_delta: room.knob.map(|k| k.delta),
                        override_remaining: room.knob.map(|k| k.until.saturating_sub(now)),
                        effective_target: room.effective_target(),
                        temperature: room.reading.map(|r| r.temperature),
                        temperature_age: room.reading.map(|r| r.age(now)),
                        desired_setpoint: room.desired,
                        reported_setpoint: room.reported_setpoint,
                        valve_temperature: room.valve_temperature,
                        valve_mode: room.valve_mode.clone(),
                        error: law.map(|(error, _, _)| error),
                        proportional: law.map(|(_, proportional, _)| proportional),
                        offset: room.offset,
                        computed_setpoint: law.map(|(_, _, setpoint)| setpoint),
                        write_pending: room.pending.is_some(),
                        writes: room.writes,
                        retries: room.retries,
                        knob_turns: room.knob_turns,
                    }
                })
                .collect(),
        }
    }

    fn persisted(&self) -> Persisted {
        Persisted {
            targets: self
                .rooms
                .iter()
                .map(|room| (room.config.name.clone(), room.target))
                .collect(),
            params: Some(self.params.clone()),
            offsets: self
                .rooms
                .iter()
                .map(|room| (room.config.name.clone(), room.offset))
                .collect(),
        }
    }

    fn expire_overrides(&mut self, now: Time) {
        for room in &mut self.rooms {
            if room.knob.is_some_and(|k| now >= k.until) {
                info!("{}: knob adjustment expired", room.config.name);
                room.knob = None;
            }
        }
    }

    fn evaluate(&mut self, now: Time) -> Vec<Action> {
        let (connected, params, limits, base_topic) =
            (self.connected, &self.params, &self.limits, &self.base_topic);
        let mut actions = Vec::new();
        let mut offsets_changed = false;
        for room in &mut self.rooms {
            let (write, offset_changed) = room.evaluate(now, connected, params, limits, base_topic);
            actions.extend(write);
            offsets_changed |= offset_changed;
        }
        if offsets_changed {
            actions.push(Action::Persist(self.persisted()));
        }
        actions
    }
}

#[cfg(test)]
mod tests;
