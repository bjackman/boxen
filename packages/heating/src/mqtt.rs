use std::time::Duration;

use anyhow::Context;
use log::{info, warn};
use rumqttc::{AsyncClient, Event, EventLoop, MqttOptions, Packet, QoS, SubscribeFilter};
use tokio::sync::mpsc;

use crate::config::MqttConfig;

#[derive(Clone, Debug, PartialEq)]
pub enum BrokerEvent {
    Connected,
    Disconnected,
    Message { topic: String, payload: Vec<u8> },
}

/// The control loop's view of MQTT. Sending only queues, so it never blocks
/// the loop.
pub trait Broker {
    /// None once the connection is gone for good.
    async fn next_event(&mut self) -> Option<BrokerEvent>;
    fn subscribe(&mut self, topics: &[String]) -> anyhow::Result<()>;
    fn publish(&mut self, topic: &str, payload: &str) -> anyhow::Result<()>;
}

const MIN_BACKOFF: Duration = Duration::from_secs(1);
const MAX_BACKOFF: Duration = Duration::from_secs(30);

pub struct MqttBroker {
    client: AsyncClient,
    events: mpsc::Receiver<BrokerEvent>,
}

impl MqttBroker {
    /// Connects in the background, and reconnects whenever the connection
    /// drops, for as long as this lives.
    pub fn spawn(config: &MqttConfig, password: String) -> Self {
        let mut options = MqttOptions::new(&config.client_id, &config.host, config.port);
        options
            .set_keep_alive(Duration::from_secs(30))
            .set_clean_session(true)
            .set_credentials(&config.username, password);
        let (client, eventloop) = AsyncClient::new(options, 64);
        let (tx, events) = mpsc::channel(256);
        tokio::spawn(drive(eventloop, tx));
        Self { client, events }
    }
}

/// rumqttc reconnects on the next poll after an error, so the backoff is ours.
async fn drive(mut eventloop: EventLoop, tx: mpsc::Sender<BrokerEvent>) {
    let mut backoff = MIN_BACKOFF;
    let mut connected = false;
    loop {
        let event = match eventloop.poll().await {
            Ok(Event::Incoming(Packet::ConnAck(_))) => {
                info!("connected to MQTT broker");
                connected = true;
                backoff = MIN_BACKOFF;
                BrokerEvent::Connected
            }
            Ok(Event::Incoming(Packet::Publish(publish))) => BrokerEvent::Message {
                topic: publish.topic,
                payload: publish.payload.to_vec(),
            },
            Ok(_) => continue,
            Err(err) => {
                warn!("MQTT connection: {err}, retrying in {backoff:?}");
                let was_connected = std::mem::replace(&mut connected, false);
                if was_connected && tx.send(BrokerEvent::Disconnected).await.is_err() {
                    return;
                }
                tokio::time::sleep(backoff).await;
                backoff = (backoff * 2).min(MAX_BACKOFF);
                continue;
            }
        };
        if tx.send(event).await.is_err() {
            return;
        }
    }
}

impl Broker for MqttBroker {
    async fn next_event(&mut self) -> Option<BrokerEvent> {
        self.events.recv().await
    }

    fn subscribe(&mut self, topics: &[String]) -> anyhow::Result<()> {
        let filters = topics
            .iter()
            .map(|topic| SubscribeFilter::new(topic.clone(), QoS::AtLeastOnce));
        self.client
            .try_subscribe_many(filters)
            .with_context(|| format!("subscribing to {topics:?}"))
    }

    fn publish(&mut self, topic: &str, payload: &str) -> anyhow::Result<()> {
        self.client
            .try_publish(topic, QoS::AtLeastOnce, false, payload)
            .with_context(|| format!("publishing to {topic}"))
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::process::{Child, Command};

    use tokio::time::timeout;

    use super::*;
    use crate::store::tests::TempDir;

    fn find_mosquitto() -> Option<PathBuf> {
        std::env::split_paths(&std::env::var_os("PATH")?)
            .map(|dir| dir.join("mosquitto"))
            .find(|path| path.is_file())
    }

    struct Mosquitto {
        binary: PathBuf,
        config_path: PathBuf,
        child: Option<Child>,
    }

    impl Mosquitto {
        fn start(binary: PathBuf, dir: &TempDir, port: u16) -> Self {
            let config_path = dir.path().join("mosquitto.conf");
            std::fs::write(
                &config_path,
                format!("listener {port} 127.0.0.1\nallow_anonymous true\n"),
            )
            .unwrap();
            let mut mosquitto = Self {
                binary,
                config_path,
                child: None,
            };
            mosquitto.restart();
            mosquitto
        }

        fn restart(&mut self) {
            self.stop();
            let child = Command::new(&self.binary)
                .arg("-c")
                .arg(&self.config_path)
                .spawn()
                .unwrap();
            self.child = Some(child);
        }

        fn stop(&mut self) {
            if let Some(mut child) = self.child.take() {
                child.kill().unwrap();
                child.wait().unwrap();
            }
        }
    }

    impl Drop for Mosquitto {
        fn drop(&mut self) {
            self.stop();
        }
    }

    async fn expect(broker: &mut MqttBroker, wanted: BrokerEvent) {
        let deadline = Duration::from_secs(20);
        loop {
            let event = timeout(deadline, broker.next_event())
                .await
                .unwrap_or_else(|_| panic!("no {wanted:?} within {deadline:?}"))
                .expect("broker task died");
            if event == wanted {
                return;
            }
        }
    }

    /// Against a real broker, when there's one on PATH (as in the Nix build).
    #[tokio::test]
    async fn talks_to_mosquitto_and_survives_it_restarting() {
        let Some(binary) = find_mosquitto() else {
            eprintln!("mosquitto not on PATH, skipping");
            return;
        };
        let dir = TempDir::new();
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let mut mosquitto = Mosquitto::start(binary, &dir, port);
        let config = MqttConfig {
            host: "127.0.0.1".into(),
            port,
            client_id: "heating-test".into(),
            username: "heating".into(),
            password_file_path: "/dev/null".into(),
            base_topic: "zigbee2mqtt".into(),
        };
        let mut broker = MqttBroker::spawn(&config, String::new());

        let message = BrokerEvent::Message {
            topic: "zigbee2mqtt/bedroom_climate".into(),
            payload: b"{}".to_vec(),
        };
        expect(&mut broker, BrokerEvent::Connected).await;
        broker
            .subscribe(&["zigbee2mqtt/bedroom_climate".into()])
            .unwrap();
        broker.publish("zigbee2mqtt/bedroom_climate", "{}").unwrap();
        expect(&mut broker, message.clone()).await;

        mosquitto.stop();
        expect(&mut broker, BrokerEvent::Disconnected).await;
        mosquitto.restart();
        expect(&mut broker, BrokerEvent::Connected).await;
        broker
            .subscribe(&["zigbee2mqtt/bedroom_climate".into()])
            .unwrap();
        broker.publish("zigbee2mqtt/bedroom_climate", "{}").unwrap();
        expect(&mut broker, message).await;
    }
}
