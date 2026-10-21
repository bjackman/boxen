use std::time::Duration;

use anyhow::bail;
use log::error;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::{Instant, sleep_until};

use crate::config::Params;
use crate::core::{Action, Controller, Snapshot};
use crate::mqtt::{Broker, BrokerEvent};
use crate::store::Store;

#[derive(Clone, Debug, PartialEq)]
pub enum CommandError {
    /// The controller refused the setting.
    Rejected(String),
    /// The setting took effect but couldn't be saved.
    NotSaved(String),
}

impl std::fmt::Display for CommandError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CommandError::Rejected(reason) => write!(f, "{reason}"),
            CommandError::NotSaved(reason) => {
                write!(
                    f,
                    "applied, but not saved, so it won't survive a restart: {reason}"
                )
            }
        }
    }
}

pub type Reply = oneshot::Sender<Result<(), CommandError>>;

pub enum Command {
    SetTarget {
        room: String,
        target: f64,
        reply: Reply,
    },
    SetParams {
        params: Params,
        reply: Reply,
    },
}

/// The controller's state as of `taken`. Ages and remaining times in it are
/// as of then.
#[derive(Clone, Debug)]
pub struct Published {
    pub snapshot: Snapshot,
    pub taken: Instant,
}

pub fn publish(controller: &Controller, start: Instant) -> Published {
    let taken = Instant::now();
    Published {
        snapshot: controller.snapshot(taken - start),
        taken,
    }
}

async fn sleep_until_deadline(deadline: Option<Instant>) {
    match deadline {
        Some(deadline) => sleep_until(deadline).await,
        None => std::future::pending().await,
    }
}

/// Carries out the actions, returning why persisting failed if it did.
/// Failed publishes are only logged: the controller retries what matters.
fn perform<B: Broker>(broker: &mut B, store: &Store, actions: Vec<Action>) -> Result<(), String> {
    let mut result = Ok(());
    for action in actions {
        match action {
            Action::Subscribe(topics) => {
                if let Err(err) = broker.subscribe(&topics) {
                    error!("{err:#}");
                }
            }
            Action::Publish { topic, payload } => {
                if let Err(err) = broker.publish(&topic, &payload) {
                    error!("{err:#}");
                }
            }
            Action::Persist(persisted) => {
                if let Err(err) = store.save(&persisted) {
                    error!("{err:#}");
                    result = Err(format!("{err:#}"));
                }
            }
        }
    }
    result
}

pub async fn run<B: Broker>(
    mut controller: Controller,
    mut broker: B,
    mut commands: mpsc::Receiver<Command>,
    published: watch::Sender<Published>,
    store: Store,
    start: Instant,
) -> anyhow::Result<()> {
    let since_start = || Instant::now() - start;
    loop {
        published.send_replace(publish(&controller, start));
        let deadline = controller
            .next_deadline(since_start())
            .map(|deadline: Duration| start + deadline);
        tokio::select! {
            event = broker.next_event() => {
                let actions = match event {
                    None => bail!("the MQTT client stopped"),
                    Some(BrokerEvent::Connected) => controller.connected(since_start()),
                    Some(BrokerEvent::Disconnected) => controller.disconnected(since_start()),
                    Some(BrokerEvent::Message { topic, payload }) => {
                        controller.message(since_start(), &topic, &payload)
                    }
                };
                let _ = perform(&mut broker, &store, actions);
            }
            Some(command) = commands.recv() => {
                let (result, reply) = match command {
                    Command::SetTarget { room, target, reply } => {
                        (controller.set_target(since_start(), &room, target), reply)
                    }
                    Command::SetParams { params, reply } => {
                        (controller.set_params(since_start(), params), reply)
                    }
                };
                let result = result
                    .map_err(CommandError::Rejected)
                    .and_then(|actions| {
                        perform(&mut broker, &store, actions).map_err(CommandError::NotSaved)
                    });
                let _ = reply.send(result);
            }
            () = sleep_until_deadline(deadline) => {
                let actions = controller.tick(since_start());
                let _ = perform(&mut broker, &store, actions);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender, unbounded_channel};
    use tokio::task::JoinHandle;

    use super::*;
    use crate::config::Config;
    use crate::core::{Persisted, Status};
    use crate::store::tests::TempDir;

    #[derive(Debug, PartialEq)]
    enum Sent {
        Subscribe(Vec<String>),
        Publish(String, serde_json::Value),
    }

    struct FakeBroker {
        events: UnboundedReceiver<BrokerEvent>,
        sent: UnboundedSender<Sent>,
    }

    impl Broker for FakeBroker {
        async fn next_event(&mut self) -> Option<BrokerEvent> {
            self.events.recv().await
        }

        fn subscribe(&mut self, topics: &[String]) -> anyhow::Result<()> {
            self.sent.send(Sent::Subscribe(topics.to_vec())).unwrap();
            Ok(())
        }

        fn publish(&mut self, topic: &str, payload: &str) -> anyhow::Result<()> {
            let payload = serde_json::from_str(payload).unwrap();
            self.sent
                .send(Sent::Publish(topic.to_owned(), payload))
                .unwrap();
            Ok(())
        }
    }

    struct Rig {
        events: UnboundedSender<BrokerEvent>,
        sent: UnboundedReceiver<Sent>,
        commands: mpsc::Sender<Command>,
        published: watch::Receiver<Published>,
        task: JoinHandle<anyhow::Result<()>>,
        _dir: TempDir,
        state_file_path: std::path::PathBuf,
    }

    fn config() -> Config {
        serde_json::from_value(json!({
            "mqtt": {
                "host": "127.0.0.1", "port": 1883, "client_id": "heating", "username": "heating",
                "password_file_path": "/dev/null", "base_topic": "zigbee2mqtt"
            },
            "http_listen": "127.0.0.1:0",
            "state_file_path": "/dev/null",
            "rooms": [
                {"name": "bedroom", "sensor": "bedroom_climate", "valve": "bedroom_radiator", "default_target": 20.0}
            ]
        }))
        .unwrap()
    }

    impl Rig {
        fn start() -> Self {
            Self::start_with_state_dir(TempDir::new(), "state.json")
        }

        fn start_with_state_dir(dir: TempDir, file_name: &str) -> Self {
            let state_file_path = dir.path().join(file_name);
            let store = Store::new(state_file_path.clone());
            let controller = Controller::new(&config(), &Persisted::default());
            let start = Instant::now();
            let (events_tx, events_rx) = unbounded_channel();
            let (sent_tx, sent_rx) = unbounded_channel();
            let (commands_tx, commands_rx) = mpsc::channel(4);
            let (published_tx, published_rx) = watch::channel(publish(&controller, start));
            let broker = FakeBroker {
                events: events_rx,
                sent: sent_tx,
            };
            let task = tokio::spawn(run(
                controller,
                broker,
                commands_rx,
                published_tx,
                store,
                start,
            ));
            Self {
                events: events_tx,
                sent: sent_rx,
                commands: commands_tx,
                published: published_rx,
                task,
                _dir: dir,
                state_file_path,
            }
        }

        fn message(&self, topic: &str, payload: serde_json::Value) {
            self.events
                .send(BrokerEvent::Message {
                    topic: topic.to_owned(),
                    payload: payload.to_string().into_bytes(),
                })
                .unwrap();
        }

        async fn next_sent(&mut self) -> Sent {
            self.sent.recv().await.unwrap()
        }

        async fn set_target(&self, target: f64) -> Result<(), CommandError> {
            let (reply, rx) = oneshot::channel();
            self.commands
                .send(Command::SetTarget {
                    room: "bedroom".into(),
                    target,
                    reply,
                })
                .await
                .unwrap();
            rx.await.unwrap()
        }

        /// Connected, valve at 20 and the room cold. Leaves the first write
        /// unconfirmed.
        async fn cold_start(&mut self) {
            self.events.send(BrokerEvent::Connected).unwrap();
            assert!(matches!(self.next_sent().await, Sent::Subscribe(_)));
            assert!(matches!(self.next_sent().await, Sent::Publish(t, _) if t.ends_with("/get")));
            self.message(
                "zigbee2mqtt/bedroom_radiator",
                json!({"occupied_heating_setpoint": 20.0, "system_mode": "heat"}),
            );
            self.message("zigbee2mqtt/bedroom_climate", json!({"temperature": 18.0}));
            assert_eq!(self.next_sent().await, set(20.5));
        }
    }

    fn set(value: f64) -> Sent {
        Sent::Publish(
            "zigbee2mqtt/bedroom_radiator/set".into(),
            json!({"occupied_heating_setpoint": value}),
        )
    }

    #[tokio::test(start_paused = true)]
    async fn retries_on_virtual_time_without_waiting_for_real() {
        let wall = std::time::Instant::now();
        let mut rig = Rig::start();
        rig.cold_start().await;
        let virtual_start = Instant::now();
        assert_eq!(rig.next_sent().await, set(20.5));
        assert_eq!(Instant::now() - virtual_start, Duration::from_secs(5 * 60));
        assert!(wall.elapsed() < Duration::from_secs(5));
        assert_eq!(rig.published.borrow().snapshot.rooms[0].retries, 1);
    }

    #[tokio::test(start_paused = true)]
    async fn steps_again_after_the_interval() {
        let mut rig = Rig::start();
        rig.cold_start().await;
        rig.message(
            "zigbee2mqtt/bedroom_radiator",
            json!({"occupied_heating_setpoint": 20.5, "system_mode": "heat"}),
        );
        let virtual_start = Instant::now();
        assert_eq!(rig.next_sent().await, set(21.0));
        assert_eq!(Instant::now() - virtual_start, Duration::from_secs(20 * 60));
    }

    #[tokio::test(start_paused = true)]
    async fn publishes_snapshots() {
        let mut rig = Rig::start();
        rig.cold_start().await;
        tokio::task::yield_now().await;
        let room = rig.published.borrow().snapshot.rooms[0].clone();
        assert_eq!(room.status, Status::Active);
        assert_eq!(room.temperature, Some(18.0));
        assert!(room.write_pending);
    }

    #[tokio::test(start_paused = true)]
    async fn the_room_goes_stale_on_time() {
        let mut rig = Rig::start();
        rig.cold_start().await;
        rig.message(
            "zigbee2mqtt/bedroom_radiator",
            json!({"occupied_heating_setpoint": 20.5, "system_mode": "heat"}),
        );
        rig.published.changed().await.unwrap();
        tokio::time::sleep(Duration::from_secs(2 * 60 * 60 + 1)).await;
        // Drain the writes made on the way, so that the loop has caught up.
        while rig.sent.try_recv().is_ok() {}
        tokio::task::yield_now().await;
        assert_eq!(
            rig.published.borrow().snapshot.rooms[0].status,
            Status::SensorStale
        );
    }

    #[tokio::test(start_paused = true)]
    async fn commands_are_applied_and_saved() {
        let rig = Rig::start();
        rig.set_target(18.5).await.unwrap();
        let saved: Persisted =
            serde_json::from_str(&std::fs::read_to_string(&rig.state_file_path).unwrap()).unwrap();
        assert_eq!(saved.targets["bedroom"], 18.5);
        assert!(rig.set_target(99.0).await.is_err());
        assert_eq!(rig.published.borrow().snapshot.rooms[0].target, 18.5);
    }

    #[tokio::test(start_paused = true)]
    async fn a_failed_save_is_reported() {
        let rig = Rig::start_with_state_dir(TempDir::new(), "missing/state.json");
        let err = rig.set_target(18.5).await.unwrap_err();
        assert!(matches!(err, CommandError::NotSaved(_)), "{err:?}");
        assert_eq!(rig.published.borrow().snapshot.rooms[0].target, 18.5);
    }

    #[tokio::test(start_paused = true)]
    async fn stops_when_the_broker_does() {
        let rig = Rig::start();
        drop(rig.events);
        assert!(rig.task.await.unwrap().is_err());
    }
}
