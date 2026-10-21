use serde_json::{Value, json};

use super::*;
use crate::config::Config;

const SENSOR: &str = "zigbee2mqtt/bedroom_climate";
const VALVE: &str = "zigbee2mqtt/bedroom_radiator";

fn config() -> Config {
    let config: Config = serde_json::from_value(json!({
        "mqtt": {
            "host": "127.0.0.1",
            "port": 1883,
            "client_id": "heating",
            "username": "heating",
            "password_file_path": "/dev/null",
            "base_topic": "zigbee2mqtt"
        },
        "http_listen": "127.0.0.1:0",
        "state_file_path": "/dev/null",
        "rooms": [
            {"name": "bedroom", "sensor": "bedroom_climate", "valve": "bedroom_radiator", "default_target": 20.0},
            {"name": "living_room", "sensor": "living_room_climate", "valve": "living_room_radiator", "default_target": 20.0}
        ]
    }))
    .unwrap();
    config.validate().unwrap();
    config
}

fn mins(m: u64) -> Time {
    Duration::from_secs(m * 60)
}

fn secs(s: u64) -> Time {
    Duration::from_secs(s)
}

/// The setpoints written to the bedroom valve.
fn writes(actions: &[Action]) -> Vec<f64> {
    actions
        .iter()
        .filter_map(|action| match action {
            Action::Publish { topic, payload } if topic == &format!("{VALVE}/set") => {
                let value: Value = serde_json::from_str(payload).unwrap();
                Some(value["occupied_heating_setpoint"].as_f64().unwrap())
            }
            _ => None,
        })
        .collect()
}

struct Harness {
    c: Controller,
}

impl Harness {
    fn new() -> Self {
        Self::with(config(), Persisted::default())
    }

    fn with(config: Config, persisted: Persisted) -> Self {
        Self {
            c: Controller::new(&config, &persisted),
        }
    }

    fn sensor(&mut self, at: Time, temperature: f64) -> Vec<Action> {
        let payload = json!({"temperature": temperature, "humidity": 55.0, "battery": 100, "linkquality": 40});
        self.c.message(at, SENSOR, payload.to_string().as_bytes())
    }

    fn valve_state(&mut self, at: Time, state: Value) -> Vec<Action> {
        self.c.message(at, VALVE, state.to_string().as_bytes())
    }

    fn valve(&mut self, at: Time, setpoint: f64) -> Vec<Action> {
        self.valve_state(
            at,
            json!({
                "occupied_heating_setpoint": setpoint,
                "system_mode": "heat",
                "local_temperature": 22.5,
                "running_state": "idle",
                "battery": 100,
            }),
        )
    }

    fn availability(&mut self, at: Time, topic: &str, payload: &str) -> Vec<Action> {
        self.c
            .message(at, &format!("{topic}/availability"), payload.as_bytes())
    }

    /// Connected, with the valve at `setpoint` and the room at `temperature`.
    /// Returns the actions of the last input.
    fn ready(&mut self, at: Time, setpoint: f64, temperature: f64) -> Vec<Action> {
        self.c.connected(at);
        self.valve(at, setpoint);
        self.sensor(at, temperature)
    }

    fn room(&self, at: Time) -> RoomSnapshot {
        self.c.snapshot(at).rooms.into_iter().next().unwrap()
    }
}

#[test]
fn connecting_subscribes_and_asks_the_valves_for_their_state() {
    let mut h = Harness::new();
    let actions = h.c.connected(secs(0));
    let Action::Subscribe(topics) = &actions[0] else {
        panic!("expected a subscription first, got {actions:?}");
    };
    for topic in [
        SENSOR.to_owned(),
        format!("{SENSOR}/availability"),
        VALVE.to_owned(),
        format!("{VALVE}/availability"),
    ] {
        assert!(topics.contains(&topic), "{topic} missing from {topics:?}");
    }
    let gets: Vec<_> = actions
        .iter()
        .filter_map(|a| match a {
            Action::Publish { topic, payload } => Some((topic.as_str(), payload.as_str())),
            _ => None,
        })
        .collect();
    assert_eq!(gets.len(), 2);
    let (topic, payload) = gets[0];
    assert_eq!(topic, format!("{VALVE}/get"));
    let payload: Value = serde_json::from_str(payload).unwrap();
    assert!(payload.get("occupied_heating_setpoint").is_some());
    assert!(payload.get("system_mode").is_some());
}

#[test]
fn does_nothing_while_disconnected() {
    let mut h = Harness::new();
    assert!(writes(&h.valve(secs(0), 20.0)).is_empty());
    assert!(writes(&h.sensor(secs(0), 15.0)).is_empty());
    assert!(writes(&h.c.tick(mins(60))).is_empty());
    assert_eq!(h.room(mins(60)).status, Status::Disconnected);
}

#[test]
fn waits_for_a_room_reading() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    assert!(writes(&h.valve(secs(0), 20.0)).is_empty());
    assert!(writes(&h.c.tick(mins(60))).is_empty());
    assert_eq!(h.room(mins(60)).status, Status::WaitingForSensor);
}

#[test]
fn waits_for_the_valve_then_acts_at_once() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    assert!(writes(&h.sensor(secs(0), 18.0)).is_empty());
    assert_eq!(h.room(secs(0)).status, Status::WaitingForValve);
    assert_eq!(writes(&h.valve(secs(10), 20.0)), [20.5]);
}

#[test]
fn waits_for_the_valve_mode() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    h.sensor(secs(0), 18.0);
    let actions = h.valve_state(secs(0), json!({"occupied_heating_setpoint": 20.0}));
    assert!(writes(&actions).is_empty());
    assert_eq!(h.room(secs(0)).status, Status::WaitingForValve);
}

#[test]
fn the_first_valve_report_is_where_it_starts_not_a_knob_turn() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    h.valve(secs(0), 24.0);
    let room = h.room(secs(0));
    assert_eq!(room.desired_setpoint, Some(24.0));
    assert_eq!(room.knob_turns, 0);
    assert_eq!(room.override_delta, None);
}

#[test]
fn steps_up_when_the_room_is_cold() {
    let mut h = Harness::new();
    assert_eq!(writes(&h.ready(secs(0), 20.0, 18.0)), [20.5]);
    let room = h.room(secs(0));
    assert!(room.write_pending);
    assert_eq!(room.writes, 1);
}

#[test]
fn steps_down_when_the_room_is_warm() {
    let mut h = Harness::new();
    assert_eq!(writes(&h.ready(secs(0), 20.0, 22.0)), [19.5]);
}

#[test]
fn holds_within_the_deadband() {
    let mut h = Harness::new();
    assert!(writes(&h.ready(secs(0), 20.0, 19.8)).is_empty());
    assert!(writes(&h.ready(secs(0), 20.0, 20.2)).is_empty());
}

#[test]
fn steps_at_most_once_per_interval() {
    let mut h = Harness::new();
    assert_eq!(writes(&h.ready(secs(0), 20.0, 18.0)), [20.5]);
    h.valve(secs(5), 20.5);
    assert!(writes(&h.sensor(mins(19), 18.0)).is_empty());
    assert_eq!(h.c.next_deadline(mins(19)), Some(mins(20)));
    assert_eq!(writes(&h.c.tick(mins(20))), [21.0]);
}

#[test]
fn a_matching_report_confirms_the_write() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    h.valve(secs(3), 20.5);
    let room = h.room(secs(3));
    assert!(!room.write_pending);
    assert_eq!(room.knob_turns, 0);
    assert_eq!(room.reported_setpoint, Some(20.5));
}

#[test]
fn a_report_of_the_old_setpoint_is_not_a_knob_turn() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    assert!(writes(&h.valve(secs(3), 20.0)).is_empty());
    let room = h.room(secs(3));
    assert!(room.write_pending);
    assert_eq!(room.knob_turns, 0);
    assert_eq!(room.desired_setpoint, Some(20.5));
}

#[test]
fn an_unconfirmed_write_is_retried_after_the_timeout() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    assert_eq!(h.c.next_deadline(secs(0)), Some(mins(5)));
    assert!(writes(&h.c.tick(mins(4))).is_empty());
    assert_eq!(writes(&h.c.tick(mins(5))), [20.5]);
    assert_eq!(h.room(mins(5)).retries, 1);
    assert_eq!(h.c.next_deadline(mins(5)), Some(mins(10)));
}

#[test]
fn never_steps_while_a_write_is_unconfirmed() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    for m in (5..=60).step_by(5) {
        let mut actions = h.sensor(mins(m), 18.0);
        actions.extend(h.c.tick(mins(m)));
        assert_eq!(writes(&actions), [20.5], "at {m} minutes");
    }
}

#[test]
fn does_not_retry_while_the_valve_is_offline() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    h.availability(mins(1), VALVE, r#"{"state":"offline"}"#);
    assert!(writes(&h.c.tick(mins(5))).is_empty());
    assert_eq!(h.room(mins(5)).status, Status::ValveOffline);
    assert_eq!(
        writes(&h.availability(mins(7), VALVE, r#"{"state":"online"}"#)),
        [20.5]
    );
}

#[test]
fn does_not_retry_while_disconnected_and_retries_on_reconnecting() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    h.c.disconnected(mins(1));
    assert!(writes(&h.c.tick(mins(5))).is_empty());
    assert_eq!(writes(&h.c.connected(mins(8))), [20.5]);
}

#[test]
fn a_knob_turn_adjusts_the_room_target_temporarily() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 19.9);
    let actions = h.valve(mins(30), 21.5);
    assert!(
        writes(&actions).is_empty(),
        "undid the knob turn: {actions:?}"
    );
    let room = h.room(mins(30));
    assert_eq!(room.knob_turns, 1);
    assert_eq!(room.override_delta, Some(1.5));
    assert_eq!(room.effective_target, 21.5);
    assert_eq!(room.desired_setpoint, Some(21.5));
    assert_eq!(room.override_remaining, Some(mins(180)));
}

#[test]
fn a_knob_turn_during_an_unconfirmed_write_is_relative_to_the_write() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    h.valve(secs(30), 22.0);
    let room = h.room(secs(30));
    assert!(!room.write_pending);
    assert_eq!(room.override_delta, Some(1.5));
    assert_eq!(room.desired_setpoint, Some(22.0));
}

#[test]
fn the_valve_gets_time_to_act_on_a_knob_turn() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 19.9);
    h.valve(mins(30), 21.0);
    // Still cold relative to the new effective target of 21.
    assert!(writes(&h.sensor(mins(31), 19.9)).is_empty());
    assert_eq!(h.c.next_deadline(mins(31)), Some(mins(50)));
    assert_eq!(writes(&h.c.tick(mins(50))), [21.5]);
}

#[test]
fn knob_turns_add_up_and_are_capped() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 19.9);
    h.valve(mins(1), 21.0);
    h.valve(mins(2), 22.0);
    assert_eq!(h.room(mins(2)).override_delta, Some(2.0));
    h.valve(mins(3), 20.0);
    assert_eq!(
        h.room(mins(3)).override_delta,
        None,
        "turning it back should cancel"
    );
    h.valve(mins(4), 30.0);
    assert_eq!(h.room(mins(4)).override_delta, Some(5.0));
}

#[test]
fn a_knob_adjustment_expires() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 19.9);
    h.valve(mins(10), 21.0);
    h.sensor(mins(100), 20.9);
    assert_eq!(h.c.next_deadline(mins(150)), Some(mins(190)));
    h.c.tick(mins(189));
    assert_eq!(h.room(mins(189)).override_delta, Some(1.0));
    h.c.tick(mins(190));
    let room = h.room(mins(190));
    assert_eq!(room.override_delta, None);
    assert_eq!(room.effective_target, 20.0);
}

#[test]
fn freezes_when_the_room_reading_goes_stale_and_resumes_on_a_fresh_one() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    h.valve(secs(5), 20.5);
    assert_eq!(writes(&h.c.tick(mins(20))), [21.0]);
    h.valve(mins(20), 21.0);
    // The sensor last reported at 0, so its reading is stale from 2h.
    assert_eq!(h.c.next_deadline(mins(100)), Some(mins(120)));
    assert!(writes(&h.c.tick(mins(120))).is_empty());
    assert_eq!(h.room(mins(120)).status, Status::SensorStale);
    assert_eq!(writes(&h.sensor(mins(130), 18.0)), [21.5]);
}

#[test]
fn freezes_while_the_sensor_is_offline() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    h.availability(secs(0), SENSOR, r#"{"state":"offline"}"#);
    h.valve(secs(0), 20.0);
    assert!(writes(&h.sensor(secs(1), 18.0)).is_empty());
    assert_eq!(h.room(secs(1)).status, Status::SensorOffline);
    assert_eq!(
        writes(&h.availability(secs(2), SENSOR, r#"{"state":"online"}"#)),
        [20.5]
    );
}

#[test]
fn freezes_while_the_valve_is_offline() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    h.availability(secs(0), VALVE, r#"{"state":"offline"}"#);
    h.valve(secs(0), 20.0);
    assert!(writes(&h.sensor(secs(1), 18.0)).is_empty());
    assert_eq!(h.room(secs(1)).status, Status::ValveOffline);
}

#[test]
fn leaves_the_valve_alone_unless_it_is_heating() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    h.sensor(secs(0), 18.0);
    let off = json!({"occupied_heating_setpoint": 20.0, "system_mode": "off"});
    assert!(writes(&h.valve_state(secs(0), off)).is_empty());
    assert_eq!(h.room(secs(0)).status, Status::ValveNotHeating);
    let auto = json!({"occupied_heating_setpoint": 20.0, "system_mode": "auto"});
    assert!(writes(&h.valve_state(secs(1), auto)).is_empty());
    assert_eq!(writes(&h.valve(secs(2), 20.0)), [20.5]);
}

#[test]
fn freezes_while_disconnected() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 19.9);
    h.c.disconnected(mins(1));
    assert!(writes(&h.sensor(mins(30), 15.0)).is_empty());
    assert!(writes(&h.c.tick(mins(40))).is_empty());
    assert_eq!(h.room(mins(40)).status, Status::Disconnected);
}

#[test]
fn keeps_the_setpoint_within_the_offset_band() {
    let mut h = Harness::new();
    // target 20, max_offset 6: 26 is the most it may ask for.
    assert!(writes(&h.ready(secs(0), 26.0, 15.0)).is_empty());

    let mut h = Harness::new();
    // Above the band and the room is fine: back into the band in one step.
    assert_eq!(writes(&h.ready(secs(0), 28.0, 20.0)), [26.0]);

    let mut h = Harness::new();
    // target 20, min_offset -4.
    assert!(writes(&h.ready(secs(0), 16.0, 25.0)).is_empty());
}

#[test]
fn the_absolute_limits_win_over_the_offset_band() {
    let mut config = config();
    config.default_params.max_offset = 15.0;
    config.rooms[0].default_target = 25.0;
    let mut h = Harness::with(config, Persisted::default());
    assert!(writes(&h.ready(secs(0), 30.0, 15.0)).is_empty());
    let mut config = self::config();
    config.default_params.min_offset = -15.0;
    config.rooms[0].default_target = 10.0;
    let mut h = Harness::with(config, Persisted::default());
    assert!(writes(&h.ready(secs(0), 5.0, 25.0)).is_empty());
}

#[test]
fn writes_whole_and_half_degrees_only() {
    let mut h = Harness::new();
    assert_eq!(writes(&h.ready(secs(0), 20.3, 18.0)), [21.0]);
}

#[test]
fn repeated_cached_state_is_not_a_knob_turn() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 19.9);
    for s in 1..10 {
        let state = json!({
            "occupied_heating_setpoint": 20.0,
            "system_mode": "heat",
            "local_temperature": 20.0 + s as f64 / 10.0,
        });
        assert!(writes(&h.valve_state(secs(s), state)).is_empty());
    }
    assert_eq!(h.room(secs(10)).knob_turns, 0);
}

#[test]
fn ignores_garbage() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    for (topic, payload) in [
        (SENSOR, &b"\xff\xfe"[..]),
        (SENSOR, b"not json"),
        (SENSOR, br#"{"temperature": "warm"}"#),
        (SENSOR, br#"[1, 2]"#),
        (SENSOR, br#"{"humidity": 50}"#),
        (VALVE, br#"{"occupied_heating_setpoint": null}"#),
        (VALVE, br#"{"system_mode": 3}"#),
        ("zigbee2mqtt/bedroom_climate/availability", b"maybe"),
        ("zigbee2mqtt/someone_else", br#"{"temperature": 5}"#),
        ("elsewhere/bedroom_climate", br#"{"temperature": 5}"#),
        ("zigbee2mqtt", br#"{"temperature": 5}"#),
    ] {
        h.c.message(secs(1), topic, payload);
    }
    let room = h.room(secs(1));
    assert_eq!(room.temperature, None);
    assert_eq!(room.reported_setpoint, None);
    assert_eq!(room.valve_mode, None);
    assert_eq!(room.status, Status::WaitingForValve);
}

#[test]
fn understands_every_availability_format() {
    let mut h = Harness::new();
    h.c.connected(secs(0));
    for (payload, online) in [
        (r#"{"state":"offline"}"#, false),
        (r#"{"state":"online"}"#, true),
        ("offline", false),
        ("online", true),
        (r#""offline""#, false),
        ("garbage", false),
    ] {
        h.availability(secs(0), VALVE, payload);
        h.valve(secs(0), 20.0);
        let status = h.room(secs(0)).status;
        assert_eq!(status == Status::ValveOffline, !online, "after {payload}");
    }
}

#[test]
fn rooms_are_independent() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    let other = &h.c.snapshot(secs(0)).rooms[1];
    assert_eq!(other.status, Status::WaitingForValve);
    assert_eq!(other.writes, 0);
    let actions = h.c.message(
        secs(1),
        "zigbee2mqtt/living_room_radiator",
        json!({"occupied_heating_setpoint": 17.0, "system_mode": "heat"})
            .to_string()
            .as_bytes(),
    );
    assert!(writes(&actions).is_empty());
    assert_eq!(h.room(secs(1)).desired_setpoint, Some(20.5));
}

#[test]
fn setting_a_target_persists_it_and_cancels_the_knob() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 19.9);
    h.valve(mins(1), 21.0);
    let actions = h.c.set_target(mins(2), "bedroom", 18.0).unwrap();
    let Action::Persist(persisted) = &actions[0] else {
        panic!("expected a persist first, got {actions:?}");
    };
    assert_eq!(persisted.targets["bedroom"], 18.0);
    assert_eq!(persisted.targets["living_room"], 20.0);
    assert_eq!(persisted.params.as_ref(), Some(&Params::default()));
    let room = h.room(mins(2));
    assert_eq!(room.target, 18.0);
    assert_eq!(room.override_delta, None);
}

#[test]
fn a_new_target_waits_for_the_step_interval() {
    let mut h = Harness::new();
    h.ready(secs(0), 20.0, 18.0);
    h.valve(secs(5), 20.5);
    let actions = h.c.set_target(mins(1), "bedroom", 15.0).unwrap();
    assert!(writes(&actions).is_empty());
    h.sensor(mins(19), 18.0);
    assert_eq!(writes(&h.c.tick(mins(20))), [20.0]);
}

#[test]
fn rejects_bad_targets() {
    let mut h = Harness::new();
    for target in [f64::NAN, f64::INFINITY, 9.9, 25.1] {
        assert!(
            h.c.set_target(secs(0), "bedroom", target).is_err(),
            "{target}"
        );
    }
    assert!(h.c.set_target(secs(0), "attic", 20.0).is_err());
    assert_eq!(h.room(secs(0)).target, 20.0);
}

#[test]
fn setting_params_persists_them_and_rejects_bad_ones() {
    let mut h = Harness::new();
    let params = Params {
        step_interval_mins: 30,
        ..Params::default()
    };
    let actions = h.c.set_params(secs(0), params.clone()).unwrap();
    assert!(matches!(&actions[0], Action::Persist(p) if p.params.as_ref() == Some(&params)));
    let bad = Params {
        step: 0.0,
        ..Params::default()
    };
    assert!(h.c.set_params(secs(0), bad).is_err());
    assert_eq!(h.c.snapshot(secs(0)).params, params);
}

#[test]
fn restores_persisted_settings_but_not_invalid_ones() {
    let persisted = Persisted {
        targets: [
            ("bedroom".to_owned(), 21.5),
            ("living_room".to_owned(), 99.0),
            ("gone".to_owned(), 18.0),
        ]
        .into_iter()
        .collect(),
        params: Some(Params {
            deadband: 0.5,
            ..Params::default()
        }),
    };
    let h = Harness::with(config(), persisted);
    let snapshot = h.c.snapshot(secs(0));
    assert_eq!(snapshot.rooms[0].target, 21.5);
    assert_eq!(snapshot.rooms[1].target, 20.0);
    assert_eq!(snapshot.params.deadband, 0.5);

    let persisted = Persisted {
        targets: BTreeMap::new(),
        params: Some(Params {
            step: -1.0,
            ..Params::default()
        }),
    };
    let h = Harness::with(config(), persisted);
    assert_eq!(h.c.snapshot(secs(0)).params, Params::default());
}

#[test]
fn deadlines_are_always_in_the_future() {
    let mut h = Harness::new();
    let check = |h: &Harness, now: Time| {
        if let Some(deadline) = h.c.next_deadline(now) {
            assert!(deadline > now, "deadline {deadline:?} at {now:?}");
        }
    };
    h.ready(secs(0), 20.0, 18.0);
    check(&h, secs(0));
    h.valve(mins(1), 22.0);
    check(&h, mins(1));
    h.availability(mins(2), VALVE, "offline");
    for m in [5, 20, 120, 181, 300] {
        h.c.tick(mins(m));
        check(&h, mins(m));
    }
}

/// A crude bedroom: the valve opens when its own sensor, which sits in the
/// radiator's warmth, is a degree below its setpoint, and the room drifts
/// towards the radiator or the outside.
#[test]
fn settles_a_simulated_room_without_oscillating_wildly() {
    let mut h = Harness::new();
    let target = 20.0;
    let mut room = 15.0;
    let mut radiator = 15.0;
    let mut open = false;
    h.c.connected(secs(0));
    let mut setpoint = 20.0;
    h.valve(secs(0), setpoint);
    let mut late_temperatures = Vec::new();
    for minute in 0..(48 * 60) {
        let now = mins(minute);
        let valve_sensor = room + (radiator - room) * 0.3;
        if valve_sensor < setpoint - 1.0 {
            open = true;
        } else if valve_sensor > setpoint {
            open = false;
        }
        radiator += if open {
            (60.0 - radiator) * 0.05
        } else {
            (room - radiator) * 0.05
        };
        room += (radiator - room) * 0.004 + (5.0 - room) * 0.002;
        let mut actions = Vec::new();
        if minute % 10 == 0 {
            actions.extend(h.sensor(now, (room * 10.0).round() / 10.0));
        }
        actions.extend(h.c.tick(now));
        if let Some(&written) = writes(&actions).last() {
            setpoint = written;
            h.valve(now, setpoint);
        }
        if minute >= 24 * 60 {
            late_temperatures.push(room);
        }
    }
    let min = late_temperatures
        .iter()
        .copied()
        .fold(f64::INFINITY, f64::min);
    let max = late_temperatures
        .iter()
        .copied()
        .fold(f64::NEG_INFINITY, f64::max);
    assert!(
        (target - 1.5..=target + 1.5).contains(&min)
            && (target - 1.5..=target + 1.5).contains(&max),
        "second day ranged {min:.1}-{max:.1} °C"
    );
}
