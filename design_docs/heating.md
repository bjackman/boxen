# heating: a radiator controller

**Status: first version, written overnight by Claude to try out. Every
decision below is open to revisiting; the ones most worth a second look are
marked _revisit_.**

## Goals

From the cascade-control design worked out with Claude before this:

1. The controller sets each room's target and reaches it with as little
   thrashing of the valve as it can.
1. Anyone can turn the knob on a valve and get a result that makes sense.
1. The flat can still be heated if the controller is down.

Plus, from the decision to write this instead of using Home Assistant:
infrastructure (which devices form a room, credentials, limits) lives in Nix,
and only policy (targets, tuning) is set at runtime, from a small web UI.

## Background

zigbee2mqtt on pizza talks to the devices and publishes each one's state as
JSON on `zigbee2mqtt/<name>`. The bedroom has a SONOFF TRVZB valve
(`bedroom_radiator`) and an SNZB-02P sensor (`bedroom_climate`).

The TRVZB regulates on its own sensor, a few centimetres from the radiator, so
it measures "air near the radiator", not the room. Cascade control keeps that
as the inner loop and adds an outer one that moves the valve's setpoint until
the room, as measured by the SNZB-02P, is at target. The valve keeps working
on its own if the outer loop stops: it just holds the last setpoint.

Home Assistant with Better Thermostat was tried first. Reading Better
Thermostat's source showed that its "target temperature based" calibration
recomputes the setpoint on every valve reading with no rate limit, and treats
a knob turn as the new absolute room target. Making Home Assistant's accounts
and integrations declarative would also have meant writing into its internal
storage. So: a small service of our own.

## Design

`packages/heating`, a Rust binary, and `nixos_modules/heating.nix`.

### A pure core and a thin shell

`core.rs` is the whole control loop as a state machine with no I/O and no
clock. Every input (a message, a connection change, a tick, a setting) comes
with the current time, and it returns actions: subscribe, publish, persist.
`next_deadline()` says when it next wants a tick. That makes every timing
scenario a plain unit test with made-up timestamps: hours of behaviour run in
microseconds, with no sleeps.

`shell.rs` is a `select!` over MQTT events, web UI commands and the next
deadline. Its tests use tokio's paused clock, where timers complete instantly
in virtual time, with an in-memory fake broker. `mqtt.rs` wraps rumqttc, and
is tested against a real Mosquitto when one is on `PATH`, which it is in the
Nix build. `tests/heating.nix` runs the NixOS module in a VM.

Time in the core is a monotonic `Duration` since start. There is no wall clock
because there is no schedule yet.

### The control law

A proportional term plus a learned offset (an integral term):

> setpoint = effective target + `kp` × error + learned offset

where error is the effective target minus the room temperature.

- The proportional term (`kp`, 1) reacts to how far off the room is now: a
  room 2 °C cold gets a setpoint 2 °C above target straight away, so the valve
  opens.
- The learned offset is what the setpoint needs on top of that to hold the
  room at target. It mostly makes up for the valve's sensor sitting in the
  radiator's warmth. Once per `step_interval` it moves by `ki` (0.25) × error,
  but only while the room is outside the `deadband` (0.3 °C) and inside the
  `integration_band` (2.5 °C), and not while the setpoint is pinned at the limit
  the error pushes it towards. So cold starts, target changes and open doors,
  which make big errors, are left to the proportional term rather than winding
  up the offset. The band has to be wider than the error the proportional
  term alone settles at, about half the valve sensor's warmth over the room
  with `kp` 1, or the offset never starts learning. It's saved with the
  settings, so a restart doesn't relearn it.
- The setpoint is kept within `min_offset`..`max_offset` (−4..+6 °C) of the
  target, and within the valve's absolute limits (5..30 °C), which win if the
  two disagree. Only whole and half degrees, as the TRVZB uses.
- It changes at most once per `step_interval` (20 minutes), and only when the
  rounded value changes.

_Revisit:_ the gains are guesses. A thermal model of the room, fed with
outdoor and neighbouring-room temperatures, could replace the learned offset
with feedforward and detect open doors and windows from its prediction error.
The plan is to fit one offline from collected data before building it in.

### The knob

A setpoint report that differs from what the controller last wanted is a turn
of the knob. Its difference is added to the room's target as an adjustment
that lasts `override_mins` (3 hours). The new setpoint is adopted as is, and
the next automatic change waits a full step interval, so the valve acts on the
turn straight away and the controller doesn't undo it. Turns add up, capped at
±5 °C, and turning back cancels the adjustment. Setting a target in the web UI
also cancels it.

zigbee2mqtt repeats a device's whole cached state in every message, so the
setpoint shows up unchanged in most valve messages. While a write is
unconfirmed, a report of the setpoint from before it means "not applied yet",
not a turn. _Revisit:_ turning the knob back to exactly that value while the
write is in flight looks the same, and gets overwritten by the retry.

_Revisit:_ the adjustment expires after a fixed time rather than "at the next
schedule block", since there is no schedule. It doesn't survive a restart.

### Freeze, don't guess

The controller changes a setpoint only when all of these hold. Otherwise it
leaves the valve alone, and the room status says why:

| Status | Condition |
|---|---|
| `disconnected` | Not connected to MQTT |
| `valve_offline` | zigbee2mqtt reports the valve offline |
| `waiting_for_valve` | Its setpoint or mode isn't known yet |
| `valve_not_heating` | Its mode isn't `heat`: someone switched it off or to its own schedule |
| `sensor_offline` | zigbee2mqtt reports the sensor offline |
| `waiting_for_sensor` | No room reading yet |
| `sensor_stale` | No room reading for 2 hours (the SNZB-02P reports at least hourly) |
| `active` | Controlling |

zigbee2mqtt retains the devices' state and stamps it with `last_seen`, when
it last heard from the device. So the controller gets each sensor's last
reading as soon as it subscribes, and judges its age from `last_seen` rather
than from when the message arrived: a reading retained or replayed from a
sensor that has since died is stale, not fresh. A message without `last_seen`
counts from its arrival. On every connection the controller also asks the
valves for their state with a `/get`.

### Writes

A write is confirmed by a valve report of the new setpoint. Until then no
other change is made, and the write is resent every 5 minutes while connected
and the valve is online. The `HeatingSetpointUnconfirmed` alert fires after 30
minutes.

### Settings

Rooms, devices and limits come from Nix. Each room's target and the tuning
parameters can be set in the web UI and are saved to
`/var/lib/heating/state.json`. A missing or corrupt file means the defaults
from Nix, on the basis that heating with defaults beats not starting.
_Revisit:_ whether anything else should be settable at runtime, and whether a
schedule should be policy (UI) or code.

## Interfaces

- **MQTT:** its own Mosquitto login. The NixOS module derives the ACL from the
  rooms: read `zigbee2mqtt/#`, write only each valve's `/set` and `/get`.
  `nixos_modules/pizza/mosquitto.nix` owns the broker and lets each client
  module register its login.
- **Web UI:** `https://heating.home.yawn.io`, behind the IAP for `brendan`.
  One page with each room's state, a target form and the tuning form. POSTs
  with a `Sec-Fetch-Site` other than `same-origin` or `none` are refused, since
  the IAP authenticates by cookie.
- **Metrics:** `/metrics`, scraped by Prometheus as job `heating`:
  `heating_room_status` (one-hot by status), targets, room and valve
  temperatures, wanted and reported setpoints, knob adjustment, and counters
  of writes, retries and knob turns. Alerts: `HeatingControllerDown`,
  `HeatingRoomUncontrolled`, `HeatingSetpointUnconfirmed`.
- **Port:** 9123, as a `bjackman.ports` fixed port, because a new allocated
  name renumbers every port that sorts after it.

## Not done yet

- The valve's own settings are still set by hand: `valve_opening_degree`
  around 55 %, from the cascade design, and finer temperature reporting on the
  bedroom sensor (0.2 °C or 30 minutes; it currently reports on whole degrees
  or hourly, which is coarse for this loop). The controller could reconcile
  these at startup.
- A schedule.
- A dashboard. The metrics are there.
- The living room has a sensor but no valve.
