use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, bail, ensure};
use serde::{Deserialize, Serialize};

/// Everything the deployment decides, as written by the NixOS module.
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub mqtt: MqttConfig,
    pub http_listen: String,
    pub state_file_path: PathBuf,
    #[serde(default)]
    pub limits: Limits,
    #[serde(default)]
    pub default_params: Params,
    pub rooms: Vec<RoomConfig>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MqttConfig {
    pub host: String,
    pub port: u16,
    pub client_id: String,
    pub username: String,
    pub password_file_path: PathBuf,
    pub base_topic: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RoomConfig {
    /// Used in metric labels and URLs, so restricted to [a-z0-9_].
    pub name: String,
    /// zigbee2mqtt friendly name of the room temperature sensor.
    pub sensor: String,
    /// zigbee2mqtt friendly name of the TRV.
    pub valve: String,
    pub default_target: f64,
}

/// Bounds that the web UI can't change.
#[derive(Clone, Debug, Deserialize, PartialEq)]
#[serde(deny_unknown_fields, default)]
pub struct Limits {
    pub setpoint_min: f64,
    pub setpoint_max: f64,
    pub target_min: f64,
    pub target_max: f64,
    pub max_override: f64,
    pub sensor_stale_after_secs: u64,
    pub write_confirm_timeout_secs: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            // The TRVZB accepts 4-35 °C.
            setpoint_min: 5.0,
            setpoint_max: 30.0,
            target_min: 10.0,
            target_max: 25.0,
            max_override: 5.0,
            // The SNZB-02P reports at least hourly.
            sensor_stale_after_secs: 2 * 60 * 60,
            write_confirm_timeout_secs: 5 * 60,
        }
    }
}

impl Limits {
    pub fn sensor_stale_after(&self) -> Duration {
        Duration::from_secs(self.sensor_stale_after_secs)
    }

    pub fn write_confirm_timeout(&self) -> Duration {
        Duration::from_secs(self.write_confirm_timeout_secs)
    }
}

/// Tuning of the control loop, adjustable from the web UI.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields, default)]
pub struct Params {
    /// Setpoint change per °C the room is off its target.
    pub kp: f64,
    /// Learned-offset change per °C off target, each step interval.
    pub ki: f64,
    /// How far the room may be from its target before the learned offset moves.
    pub deadband: f64,
    /// How far the room may be from its target for the learned offset to move.
    /// Bigger errors come from cold starts, target changes and open doors, and
    /// are left to the proportional term rather than winding up the offset.
    pub integration_band: f64,
    /// Minimum time between setpoint changes, and between updates of the
    /// learned offset.
    pub step_interval_mins: u64,
    /// The setpoint is kept within these offsets of the room's effective target.
    pub min_offset: f64,
    pub max_offset: f64,
    /// How long a turn of the knob adjusts the room target for.
    pub override_mins: u64,
}

impl Default for Params {
    fn default() -> Self {
        Self {
            kp: 1.0,
            ki: 0.25,
            deadband: 0.3,
            integration_band: 2.5,
            step_interval_mins: 20,
            min_offset: -4.0,
            max_offset: 6.0,
            override_mins: 180,
        }
    }
}

impl Params {
    /// Parses params saved by any version, dropping fields it doesn't know,
    /// such as ones an older version had.
    pub fn from_saved(saved: serde_json::Value) -> anyhow::Result<Self> {
        let known = serde_json::to_value(Params::default()).context("listing params")?;
        let mut fields = match saved {
            serde_json::Value::Object(fields) => fields,
            other => anyhow::bail!("saved params aren't an object: {other}"),
        };
        fields.retain(|name, _| known.get(name).is_some());
        serde_json::from_value(serde_json::Value::Object(fields)).context("parsing saved params")
    }

    pub fn step_interval(&self) -> Duration {
        Duration::from_secs(self.step_interval_mins * 60)
    }

    pub fn override_duration(&self) -> Duration {
        Duration::from_secs(self.override_mins * 60)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        ensure!(
            self.deadband.is_finite() && (0.0..=5.0).contains(&self.deadband),
            "deadband must be between 0 and 5 °C"
        );
        ensure!(
            self.kp.is_finite() && (0.0..=10.0).contains(&self.kp),
            "kp must be between 0 and 10"
        );
        ensure!(
            self.ki.is_finite() && (0.0..=5.0).contains(&self.ki),
            "ki must be between 0 and 5"
        );
        ensure!(
            self.integration_band.is_finite() && (0.0..=10.0).contains(&self.integration_band),
            "integration band must be between 0 and 10 °C"
        );
        ensure!(
            (1..=24 * 60).contains(&self.step_interval_mins),
            "step interval must be between 1 minute and 24 hours"
        );
        ensure!(
            self.min_offset.is_finite()
                && self.max_offset.is_finite()
                && self.min_offset <= self.max_offset,
            "min offset must not exceed max offset"
        );
        ensure!(
            (-15.0..=15.0).contains(&self.min_offset) && (-15.0..=15.0).contains(&self.max_offset),
            "offsets must be between -15 and 15 °C"
        );
        ensure!(
            (1..=7 * 24 * 60).contains(&self.override_mins),
            "override duration must be between 1 minute and 7 days"
        );
        Ok(())
    }
}

impl Config {
    pub fn load(path: &Path) -> anyhow::Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("reading config {}", path.display()))?;
        let config: Config = serde_json::from_str(&text)
            .with_context(|| format!("parsing config {}", path.display()))?;
        config
            .validate()
            .with_context(|| format!("validating config {}", path.display()))?;
        Ok(config)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        let limits = &self.limits;
        ensure!(
            limits.setpoint_min < limits.setpoint_max,
            "setpoint_min must be below setpoint_max"
        );
        ensure!(
            limits.target_min < limits.target_max,
            "target_min must be below target_max"
        );
        ensure!(
            limits.max_override >= 0.0,
            "max_override must not be negative"
        );
        ensure!(
            limits.sensor_stale_after_secs > 0 && limits.write_confirm_timeout_secs > 0,
            "timeouts must be positive"
        );
        self.default_params
            .validate()
            .context("checking default_params")?;
        ensure!(!self.rooms.is_empty(), "no rooms configured");

        let mut names = HashSet::new();
        let mut devices = HashSet::new();
        for room in &self.rooms {
            ensure!(
                !room.name.is_empty()
                    && room
                        .name
                        .chars()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_'),
                "room name {:?} must be non-empty [a-z0-9_]",
                room.name
            );
            ensure!(
                names.insert(&room.name),
                "room {:?} appears twice",
                room.name
            );
            for device in [&room.sensor, &room.valve] {
                if device.is_empty() || device.contains(['/', '#', '+']) {
                    bail!(
                        "device name {device:?} in room {:?} isn't a plain MQTT topic level",
                        room.name
                    );
                }
                ensure!(devices.insert(device), "device {device:?} is used twice");
            }
            ensure!(
                (limits.target_min..=limits.target_max).contains(&room.default_target),
                "default target of room {:?} is outside the target limits",
                room.name
            );
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn example() -> Config {
        serde_json::from_value(serde_json::json!({
            "mqtt": {
                "host": "127.0.0.1",
                "port": 1883,
                "client_id": "heating",
                "username": "heating",
                "password_file_path": "/run/credentials/heating.service/mqtt-password",
                "base_topic": "zigbee2mqtt"
            },
            "http_listen": "127.0.0.1:9009",
            "state_file_path": "/var/lib/heating/state.json",
            "rooms": [
                {"name": "bedroom", "sensor": "bedroom_climate", "valve": "bedroom_radiator", "default_target": 20.0}
            ]
        }))
        .unwrap()
    }

    #[test]
    fn example_is_valid_with_defaults() {
        let config = example();
        config.validate().unwrap();
        assert_eq!(config.limits, Limits::default());
        assert_eq!(config.default_params, Params::default());
    }

    #[test]
    fn rejects_unknown_fields_in_the_config() {
        let mqtt = serde_json::json!({
            "host": "127.0.0.1", "port": 1883, "client_id": "heating", "username": "heating",
            "password_file_path": "/dev/null", "base_topic": "zigbee2mqtt", "typo": 1
        });
        assert!(serde_json::from_value::<MqttConfig>(mqtt).is_err());
        let typo = serde_json::json!({"kpp": 1.0});
        assert!(serde_json::from_value::<Params>(typo).is_err());
    }

    #[test]
    fn saved_params_from_an_older_version_still_load() {
        let old = Params::from_saved(serde_json::json!({"deadband": 0.5, "step": 0.5})).unwrap();
        assert_eq!(old.deadband, 0.5);
        assert_eq!(old.kp, Params::default().kp);
        assert!(Params::from_saved(serde_json::json!([1])).is_err());
        assert!(Params::from_saved(serde_json::json!({"kp": "high"})).is_err());
    }

    #[test]
    fn rejects_bad_room_names() {
        for name in ["", "Bedroom", "bed room", "bed\"room"] {
            let mut config = example();
            config.rooms[0].name = name.into();
            assert!(config.validate().is_err(), "{name:?} accepted");
        }
    }

    #[test]
    fn rejects_wildcard_device_names() {
        for device in ["a/b", "#", "+", ""] {
            let mut config = example();
            config.rooms[0].valve = device.into();
            assert!(config.validate().is_err(), "{device:?} accepted");
        }
    }

    #[test]
    fn rejects_shared_devices_and_duplicate_rooms() {
        let mut config = example();
        let mut other = config.rooms[0].clone();
        other.name = "office".into();
        config.rooms.push(other);
        assert!(config.validate().is_err());

        let mut config = example();
        let mut other = config.rooms[0].clone();
        other.sensor = "office_climate".into();
        other.valve = "office_radiator".into();
        config.rooms.push(other);
        assert!(config.validate().is_err());
    }

    #[test]
    fn rejects_default_target_out_of_range() {
        let mut config = example();
        config.rooms[0].default_target = 40.0;
        assert!(config.validate().is_err());
    }

    #[test]
    fn params_validation() {
        Params::default().validate().unwrap();
        let bad = [
            Params {
                deadband: f64::NAN,
                ..Params::default()
            },
            Params {
                kp: -1.0,
                ..Params::default()
            },
            Params {
                ki: f64::NAN,
                ..Params::default()
            },
            Params {
                step_interval_mins: 0,
                ..Params::default()
            },
            Params {
                min_offset: 3.0,
                max_offset: 2.0,
                ..Params::default()
            },
            Params {
                max_offset: 50.0,
                ..Params::default()
            },
            Params {
                override_mins: 0,
                ..Params::default()
            },
        ];
        for params in bad {
            assert!(params.validate().is_err(), "{params:?} accepted");
        }
    }
}
