mod config;
mod core;
mod http;
mod mqtt;
mod shell;
mod store;

use std::path::PathBuf;

use anyhow::Context;
use tokio::net::TcpListener;
use tokio::sync::{mpsc, watch};
use tokio::time::Instant;

use crate::config::Config;
use crate::core::Controller;
use crate::http::AppState;
use crate::mqtt::MqttBroker;
use crate::store::Store;

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp(None)
        .init();
    let config_path: PathBuf = std::env::args_os()
        .nth(1)
        .context("usage: heating CONFIG_PATH")?
        .into();
    let config = Config::load(&config_path)?;
    let password_path = &config.mqtt.password_file_path;
    let password = std::fs::read_to_string(password_path)
        .with_context(|| format!("reading MQTT password from {}", password_path.display()))?
        .trim_end()
        .to_owned();

    let store = Store::new(config.state_file_path.clone());
    let controller = Controller::new(&config, &store.load());
    let start = Instant::now();
    let (published_tx, published) = watch::channel(shell::publish(&controller, start));
    let (commands_tx, commands) = mpsc::channel(16);

    let listener = TcpListener::bind(&config.http_listen)
        .await
        .with_context(|| format!("listening on {}", config.http_listen))?;
    let app = http::router(AppState {
        published,
        commands: commands_tx,
    });
    let broker = MqttBroker::spawn(&config.mqtt, password);

    tokio::select! {
        result = shell::run(controller, broker, commands, published_tx, store, start) => result,
        result = axum::serve(listener, app) => result.context("serving HTTP"),
    }
}
