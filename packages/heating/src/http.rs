use std::fmt::Write;
use std::time::Duration;

use axum::Router;
use axum::extract::{Form, Request, State};
use axum::http::{HeaderValue, Method, StatusCode, header};
use axum::middleware::{self, Next};
use axum::response::{Html, IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use serde::Deserialize;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::Instant;

use crate::config::Params;
use crate::core::{RoomSnapshot, Status};
use crate::shell::{Command, CommandError, Published, Reply};

#[derive(Clone)]
pub struct AppState {
    pub published: watch::Receiver<Published>,
    pub commands: mpsc::Sender<Command>,
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/metrics", get(metrics))
        .route("/target", post(set_target))
        .route("/params", post(set_params))
        .layer(middleware::from_fn(refuse_cross_site))
        .with_state(state)
}

/// The IAP authenticates by cookie, so a page elsewhere could otherwise post
/// forms here with the user's session. Browsers say where a request came from
/// in Sec-Fetch-Site; anything without the header isn't a browser.
async fn refuse_cross_site(request: Request, next: Next) -> Response {
    let safe = matches!(*request.method(), Method::GET | Method::HEAD);
    let site = request.headers().get("sec-fetch-site");
    let allowed = |site: &HeaderValue| site == "same-origin" || site == "none";
    if !safe && site.is_some_and(|site| !allowed(site)) {
        return (StatusCode::FORBIDDEN, "cross-site request refused\n").into_response();
    }
    next.run(request).await
}

async fn send(state: &AppState, command: impl FnOnce(Reply) -> Command) -> Response {
    let (reply, rx) = oneshot::channel();
    if state.commands.send(command(reply)).await.is_err() {
        return (StatusCode::SERVICE_UNAVAILABLE, "controller not running\n").into_response();
    }
    match rx.await {
        Ok(Ok(())) => Redirect::to("/").into_response(),
        Ok(Err(err @ CommandError::Rejected(_))) => {
            (StatusCode::BAD_REQUEST, format!("{err}\n")).into_response()
        }
        Ok(Err(err @ CommandError::NotSaved(_))) => {
            (StatusCode::INTERNAL_SERVER_ERROR, format!("{err}\n")).into_response()
        }
        Err(_) => (StatusCode::SERVICE_UNAVAILABLE, "controller not running\n").into_response(),
    }
}

#[derive(Deserialize)]
struct TargetForm {
    room: String,
    target: f64,
}

async fn set_target(State(state): State<AppState>, Form(form): Form<TargetForm>) -> Response {
    send(&state, |reply| Command::SetTarget {
        room: form.room,
        target: form.target,
        reply,
    })
    .await
}

/// Unlike `Params`, every field is required, so that a partial form is
/// refused rather than resetting what it leaves out.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ParamsForm {
    kp: f64,
    ki: f64,
    deadband: f64,
    integration_band: f64,
    step_interval_mins: u64,
    min_offset: f64,
    max_offset: f64,
    override_mins: u64,
}

async fn set_params(State(state): State<AppState>, Form(form): Form<ParamsForm>) -> Response {
    let params = Params {
        kp: form.kp,
        ki: form.ki,
        deadband: form.deadband,
        integration_band: form.integration_band,
        step_interval_mins: form.step_interval_mins,
        min_offset: form.min_offset,
        max_offset: form.max_offset,
        override_mins: form.override_mins,
    };
    send(&state, |reply| Command::SetParams { params, reply }).await
}

async fn index(State(state): State<AppState>) -> Html<String> {
    Html(render_index(&state.published.borrow(), Instant::now()))
}

async fn metrics(State(state): State<AppState>) -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        render_metrics(&state.published.borrow(), Instant::now()),
    )
}

fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn temperature(value: Option<f64>) -> String {
    value.map_or_else(|| "?".to_owned(), |v| format!("{v:.1} °C"))
}

fn minutes(duration: Duration) -> String {
    format!("{} min", duration.as_secs() / 60)
}

fn render_room(room: &RoomSnapshot, elapsed: Duration, out: &mut String) {
    let name = escape(&room.name);
    let age = room.temperature_age.map(|age| age + elapsed);
    let knob = match (room.override_delta, room.override_remaining) {
        (Some(delta), Some(remaining)) => format!(
            "{delta:+.1} °C for {}",
            minutes(remaining.saturating_sub(elapsed))
        ),
        _ => "none".to_owned(),
    };
    let _ = write!(
        out,
        r#"<section>
<h2>{name}</h2>
<table>
<tr><th>Status</th><td>{status}</td></tr>
<tr><th>Room</th><td>{temperature}{age}</td></tr>
<tr><th>Target</th><td>{target:.1} °C, knob {knob}, so aiming for {effective:.1} °C</td></tr>
<tr><th>Control</th><td>{control}</td></tr>
<tr><th>Valve setpoint</th><td>wanted {desired}, reported {reported}{pending}</td></tr>
<tr><th>Valve</th><td>{valve_temperature}, mode {mode}</td></tr>
<tr><th>Counts</th><td>{writes} writes, {retries} retries, {knob_turns} knob turns</td></tr>
</table>
<form method="post" action="/target">
<input type="hidden" name="room" value="{name}">
<label>New target <input name="target" type="number" step="0.5" value="{target:.1}"></label>
<button>Set</button>
</form>
</section>
"#,
        status = room.status.as_str(),
        control = match (room.error, room.proportional, room.computed_setpoint) {
            (Some(error), Some(proportional), Some(setpoint)) => format!(
                "error {error:+.1} °C, proportional {proportional:+.1} °C, learned offset {:+.2} °C, so setpoint {setpoint:.1} °C",
                room.offset
            ),
            _ => format!(
                "learned offset {:+.2} °C, no reading to act on",
                room.offset
            ),
        },
        temperature = temperature(room.temperature),
        age = age.map_or_else(String::new, |age| format!(", {} ago", minutes(age))),
        target = room.target,
        effective = room.effective_target,
        desired = temperature(room.desired_setpoint),
        reported = temperature(room.reported_setpoint),
        pending = if room.write_pending {
            " (unconfirmed)"
        } else {
            ""
        },
        valve_temperature = temperature(room.valve_temperature),
        mode = escape(room.valve_mode.as_deref().unwrap_or("?")),
        writes = room.writes,
        retries = room.retries,
        knob_turns = room.knob_turns,
    );
}

pub fn render_index(published: &Published, now: Instant) -> String {
    let snapshot = &published.snapshot;
    let elapsed = now.saturating_duration_since(published.taken);
    let mut out = String::from(
        r#"<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Heating</title>
<style>
body { font-family: sans-serif; max-width: 40em; margin: 1em auto; padding: 0 1em; }
th { text-align: left; padding-right: 1em; }
section { margin-bottom: 2em; }
</style>
</head>
<body>
<h1>Heating</h1>
"#,
    );
    let _ = writeln!(
        out,
        "<p>MQTT {}</p>",
        if snapshot.connected {
            "connected"
        } else {
            "disconnected"
        }
    );
    for room in &snapshot.rooms {
        render_room(room, elapsed, &mut out);
    }
    let p = &snapshot.params;
    let _ = write!(
        out,
        r#"<h2>Tuning</h2>
<form method="post" action="/params">
<table>
<tr><th><label for="kp">Kp (°C per °C off target)</label></th><td><input id="kp" name="kp" type="number" step="0.05" value="{}"></td></tr>
<tr><th><label for="ki">Ki (°C per °C off target, per interval)</label></th><td><input id="ki" name="ki" type="number" step="0.05" value="{}"></td></tr>
<tr><th><label for="deadband">Deadband (°C)</label></th><td><input id="deadband" name="deadband" type="number" step="0.1" value="{}"></td></tr>
<tr><th><label for="integration_band">Integration band (°C)</label></th><td><input id="integration_band" name="integration_band" type="number" step="0.1" value="{}"></td></tr>
<tr><th><label for="step_interval_mins">Step interval (min)</label></th><td><input id="step_interval_mins" name="step_interval_mins" type="number" value="{}"></td></tr>
<tr><th><label for="min_offset">Min offset (°C)</label></th><td><input id="min_offset" name="min_offset" type="number" step="0.5" value="{}"></td></tr>
<tr><th><label for="max_offset">Max offset (°C)</label></th><td><input id="max_offset" name="max_offset" type="number" step="0.5" value="{}"></td></tr>
<tr><th><label for="override_mins">Knob override (min)</label></th><td><input id="override_mins" name="override_mins" type="number" value="{}"></td></tr>
</table>
<button>Save</button>
</form>
</body>
</html>
"#,
        p.kp,
        p.ki,
        p.deadband,
        p.integration_band,
        p.step_interval_mins,
        p.min_offset,
        p.max_offset,
        p.override_mins
    );
    out
}

struct Metrics(String);

impl Metrics {
    fn family(&mut self, name: &str, kind: &str, help: &str) {
        let _ = writeln!(self.0, "# HELP {name} {help}\n# TYPE {name} {kind}");
    }

    fn sample(&mut self, name: &str, labels: &str, value: impl std::fmt::Display) {
        let _ = writeln!(self.0, "{name}{{{labels}}} {value}");
    }

    fn rooms(
        &mut self,
        name: &str,
        kind: &str,
        help: &str,
        rooms: &[RoomSnapshot],
        value: impl Fn(&RoomSnapshot) -> Option<f64>,
    ) {
        self.family(name, kind, help);
        for room in rooms {
            if let Some(v) = value(room) {
                self.sample(name, &format!("room=\"{}\"", room.name), v);
            }
        }
    }
}

/// Room names are restricted to [a-z0-9_] by the config, so they need no
/// escaping as label values.
pub fn render_metrics(published: &Published, now: Instant) -> String {
    let snapshot = &published.snapshot;
    let elapsed = now.saturating_duration_since(published.taken);
    let rooms = &snapshot.rooms;
    let mut m = Metrics(String::new());
    m.family(
        "heating_mqtt_connected",
        "gauge",
        "Whether the controller is connected to MQTT.",
    );
    let _ = writeln!(
        m.0,
        "heating_mqtt_connected {}",
        u8::from(snapshot.connected)
    );
    m.family(
        "heating_room_status",
        "gauge",
        "1 for the room's current control status, 0 for the others.",
    );
    for room in rooms {
        for status in Status::ALL {
            let labels = format!("room=\"{}\",status=\"{}\"", room.name, status.as_str());
            m.sample(
                "heating_room_status",
                &labels,
                u8::from(room.status == status),
            );
        }
    }
    m.rooms(
        "heating_target_celsius",
        "gauge",
        "Room target set in the UI.",
        rooms,
        |r| Some(r.target),
    );
    m.rooms(
        "heating_effective_target_celsius",
        "gauge",
        "Room target including any knob adjustment.",
        rooms,
        |r| Some(r.effective_target),
    );
    m.rooms(
        "heating_knob_adjustment_celsius",
        "gauge",
        "Current adjustment of the room target from turning the valve's knob.",
        rooms,
        |r| Some(r.override_delta.unwrap_or(0.0)),
    );
    m.rooms(
        "heating_room_temperature_celsius",
        "gauge",
        "Last room temperature reading.",
        rooms,
        |r| r.temperature,
    );
    m.rooms(
        "heating_room_temperature_age_seconds",
        "gauge",
        "Time since the last room temperature reading.",
        rooms,
        |r| r.temperature_age.map(|age| (age + elapsed).as_secs_f64()),
    );
    m.rooms(
        "heating_valve_setpoint_wanted_celsius",
        "gauge",
        "Setpoint the controller wants the valve to have.",
        rooms,
        |r| r.desired_setpoint,
    );
    m.rooms(
        "heating_valve_setpoint_reported_celsius",
        "gauge",
        "Setpoint the valve last reported.",
        rooms,
        |r| r.reported_setpoint,
    );
    m.rooms(
        "heating_valve_temperature_celsius",
        "gauge",
        "Temperature at the valve's own sensor.",
        rooms,
        |r| r.valve_temperature,
    );
    m.rooms(
        "heating_valve_write_pending",
        "gauge",
        "Whether a setpoint write is awaiting confirmation.",
        rooms,
        |r| Some(f64::from(u8::from(r.write_pending))),
    );
    m.rooms(
        "heating_setpoint_writes_total",
        "counter",
        "Setpoint changes sent.",
        rooms,
        |r| Some(r.writes as f64),
    );
    m.rooms(
        "heating_setpoint_retries_total",
        "counter",
        "Setpoint writes resent for lack of confirmation.",
        rooms,
        |r| Some(r.retries as f64),
    );
    m.rooms(
        "heating_knob_turns_total",
        "counter",
        "Turns of the valve's knob noticed.",
        rooms,
        |r| Some(r.knob_turns as f64),
    );
    m.0
}

#[cfg(test)]
mod tests {
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use serde_json::json;
    use tower::ServiceExt;

    use super::*;
    use crate::config::Config;
    use crate::core::{Controller, Persisted};
    use crate::shell::publish;

    fn controller() -> Controller {
        let config: Config = serde_json::from_value(json!({
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
        .unwrap();
        let mut controller = Controller::new(&config, &Persisted::default());
        let start = Duration::ZERO;
        controller.connected(start);
        let valve = json!({"occupied_heating_setpoint": 20.0, "system_mode": "<script>", "local_temperature": 23.0, "running_state": "idle"});
        controller.message(
            start,
            Duration::ZERO,
            "zigbee2mqtt/bedroom_radiator",
            valve.to_string().as_bytes(),
        );
        controller.message(
            start,
            Duration::ZERO,
            "zigbee2mqtt/bedroom_climate",
            br#"{"temperature": 19.5}"#,
        );
        controller
    }

    /// Answers every command with `result`, recording what it got.
    fn app(result: Result<(), CommandError>) -> (Router, mpsc::UnboundedReceiver<String>) {
        let controller = controller();
        let (_published_tx, published) = watch::channel(publish(&controller, Instant::now()));
        let (commands, mut rx) = mpsc::channel(4);
        let (seen_tx, seen) = mpsc::unbounded_channel();
        tokio::spawn(async move {
            let _keep = _published_tx;
            while let Some(command) = rx.recv().await {
                let (description, reply) = match command {
                    Command::SetTarget {
                        room,
                        target,
                        reply,
                    } => (format!("target {room} {target}"), reply),
                    Command::SetParams { params, reply } => (format!("params {params:?}"), reply),
                };
                let _ = seen_tx.send(description);
                let _ = reply.send(result.clone());
            }
        });
        (
            router(AppState {
                published,
                commands,
            }),
            seen,
        )
    }

    fn post(uri: &str, body: &str, site: Option<&str>) -> Request<Body> {
        let mut request =
            Request::post(uri).header(header::CONTENT_TYPE, "application/x-www-form-urlencoded");
        if let Some(site) = site {
            request = request.header("sec-fetch-site", site);
        }
        request.body(Body::from(body.to_owned())).unwrap()
    }

    async fn body(response: Response) -> String {
        String::from_utf8(
            response
                .into_body()
                .collect()
                .await
                .unwrap()
                .to_bytes()
                .to_vec(),
        )
        .unwrap()
    }

    #[tokio::test]
    async fn the_page_shows_rooms_and_escapes_device_text() {
        let (app, _) = app(Ok(()));
        let response = app
            .oneshot(Request::get("/").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let html = body(response).await;
        assert!(html.contains("<h2>bedroom</h2>"));
        assert!(html.contains("19.5 °C"));
        assert!(html.contains("mode &lt;script&gt;"));
        assert!(!html.contains("<script>"));
    }

    #[tokio::test]
    async fn metrics_cover_the_room() {
        let (app, _) = app(Ok(()));
        let response = app
            .oneshot(Request::get("/metrics").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let text = body(response).await;
        for line in [
            "heating_mqtt_connected 1",
            r#"heating_room_temperature_celsius{room="bedroom"} 19.5"#,
            r#"heating_target_celsius{room="bedroom"} 20"#,
            r#"heating_valve_setpoint_reported_celsius{room="bedroom"} 20"#,
            r#"heating_room_status{room="bedroom",status="valve_not_heating"} 1"#,
            r#"heating_room_status{room="bedroom",status="active"} 0"#,
            r#"heating_knob_adjustment_celsius{room="bedroom"} 0"#,
        ] {
            assert!(
                text.lines().any(|l| l == line),
                "missing {line:?} in:\n{text}"
            );
        }
        for family in text.lines().filter_map(|l| l.strip_prefix("# TYPE ")) {
            let name = family.split(' ').next().unwrap();
            assert_eq!(
                text.matches(&format!("# TYPE {name} ")).count(),
                1,
                "{name} declared twice"
            );
        }
    }

    #[tokio::test]
    async fn setting_a_target_redirects_back() {
        let (app, mut seen) = app(Ok(()));
        let response = app
            .oneshot(post(
                "/target",
                "room=bedroom&target=19.5",
                Some("same-origin"),
            ))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::SEE_OTHER);
        assert_eq!(response.headers()[header::LOCATION], "/");
        assert_eq!(seen.recv().await.unwrap(), "target bedroom 19.5");
    }

    #[tokio::test]
    async fn the_controller_s_refusal_is_shown() {
        let (app, _) = app(Err(CommandError::Rejected(
            "target must be between 10 and 25 °C".into(),
        )));
        let response = app
            .oneshot(post("/target", "room=bedroom&target=99", None))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert!(body(response).await.contains("between 10 and 25"));
    }

    #[tokio::test]
    async fn a_failed_save_is_a_server_error() {
        let (app, _) = app(Err(CommandError::NotSaved("disk full".into())));
        let response = app
            .oneshot(post("/target", "room=bedroom&target=19.5", None))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
        let text = body(response).await;
        assert!(
            text.contains("applied, but not saved") && text.contains("disk full"),
            "{text}"
        );
    }

    #[tokio::test]
    async fn refuses_cross_site_posts() {
        for site in ["cross-site", "same-site"] {
            let (app, mut seen) = app(Ok(()));
            let response = app
                .oneshot(post("/target", "room=bedroom&target=19.5", Some(site)))
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::FORBIDDEN, "{site}");
            assert!(seen.try_recv().is_err(), "{site} reached the controller");
        }
    }

    #[tokio::test]
    async fn malformed_forms_never_reach_the_controller() {
        for body in ["room=bedroom", "room=bedroom&target=warm", "target=19"] {
            let (app, mut seen) = app(Ok(()));
            let response = app.oneshot(post("/target", body, None)).await.unwrap();
            assert!(
                response.status().is_client_error(),
                "{body}: {}",
                response.status()
            );
            assert!(seen.try_recv().is_err(), "{body} reached the controller");
        }
    }

    #[tokio::test]
    async fn partial_params_never_reach_the_controller() {
        for body in [
            "deadband=0.5",
            "kp=1.5&ki=0.1&deadband=0.5&integration_band=1.5&step_interval_mins=30&min_offset=-3&max_offset=5",
            "kp=1.5&ki=0.1&deadband=0.5&integration_band=1.5&step_interval_mins=30&min_offset=-3&max_offset=5&override_mins=60&typo=1",
        ] {
            let (app, mut seen) = app(Ok(()));
            let response = app.oneshot(post("/params", body, None)).await.unwrap();
            assert!(
                response.status().is_client_error(),
                "{body}: {}",
                response.status()
            );
            assert!(seen.try_recv().is_err(), "{body} reached the controller");
        }
    }

    #[tokio::test]
    async fn sets_params() {
        let (app, mut seen) = app(Ok(()));
        let form = "kp=1.5&ki=0.1&deadband=0.5&integration_band=1.5&step_interval_mins=30&min_offset=-3&max_offset=5&override_mins=60";
        let response = app
            .oneshot(post("/params", form, Some("same-origin")))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::SEE_OTHER);
        let expected = Params {
            kp: 1.5,
            ki: 0.1,
            deadband: 0.5,
            integration_band: 1.5,
            step_interval_mins: 30,
            min_offset: -3.0,
            max_offset: 5.0,
            override_mins: 60,
        };
        assert_eq!(seen.recv().await.unwrap(), format!("params {expected:?}"));
    }
}
