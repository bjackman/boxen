# The heating controller's NixOS module against a real Mosquitto, with
# anonymous clients standing in for zigbee2mqtt's devices. The controller logs
# in with the ACL the module derives.
{ pkgs }:
let
  port = 9123;
  url = "http://127.0.0.1:${toString port}";
  password = pkgs.writeText "heating-mqtt-password" "hunter2";
in
pkgs.testers.runNixOSTest {
  name = "heating";
  nodes.machine =
    { config, ... }:
    {
      imports = [ ../nixos_modules/heating.nix ];
      bjackman.heating = {
        enable = true;
        inherit port;
        rooms = [
          {
            name = "bedroom";
            sensor = "bedroom_climate";
            valve = "bedroom_radiator";
            defaultTarget = 20.0;
          }
        ];
        mqtt.passwordFilePath = "${password}";
      };
      services.mosquitto = {
        enable = true;
        listeners = [
          {
            address = "127.0.0.1";
            port = 1883;
            settings.listener_allow_anonymous = true;
            acl = [ "topic readwrite #" ];
            users.heating = {
              passwordFile = password;
              inherit (config.bjackman.heating.mqtt) acl;
            };
          }
        ];
      };
      environment.systemPackages = [
        pkgs.curl
        pkgs.mosquitto
      ];
    };

  testScript = ''
    import json

    machine.wait_for_unit("mosquitto.service")
    machine.wait_for_unit("heating.service")
    machine.wait_until_succeeds("curl -sf ${url}/metrics | grep -qx 'heating_mqtt_connected 1'")

    with subtest("a cold room gets a higher setpoint"):
        machine.succeed(
            "systemd-run --unit=watch-valve sh -c "
            "'${pkgs.coreutils}/bin/stdbuf -oL ${pkgs.mosquitto}/bin/mosquitto_sub -h 127.0.0.1 -v -t zigbee2mqtt/bedroom_radiator/set -t test/ping >/tmp/valve.log'"
        )
        machine.wait_until_succeeds(
            "mosquitto_pub -h 127.0.0.1 -t test/ping -m ping && grep -q ping /tmp/valve.log"
        )
        valve = json.dumps({"occupied_heating_setpoint": 20.0, "system_mode": "heat"})
        machine.succeed(f"mosquitto_pub -h 127.0.0.1 -t zigbee2mqtt/bedroom_radiator -m '{valve}'")
        machine.succeed("""mosquitto_pub -h 127.0.0.1 -t zigbee2mqtt/bedroom_climate -m '{"temperature": 15}'""")
        machine.wait_until_succeeds(
            """grep -qx 'zigbee2mqtt/bedroom_radiator/set {"occupied_heating_setpoint":20.5}' /tmp/valve.log"""
        )
        metrics = machine.succeed("curl -sf ${url}/metrics")
        assert 'heating_room_status{room="bedroom",status="active"} 1' in metrics, metrics

    with subtest("the web UI shows the room and refuses cross-site posts"):
        machine.succeed("curl -sf ${url}/ | grep -q '<h2>bedroom</h2>'")
        status = machine.succeed(
            "curl -s -o /dev/null -w '%{http_code}' -H 'Sec-Fetch-Site: cross-site' "
            "-d room=bedroom -d target=18 ${url}/target"
        )
        assert status == "403", status

    with subtest("a target set in the UI survives a restart"):
        status = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -d room=bedroom -d target=18 ${url}/target")
        assert status == "303", status
        machine.succeed("systemctl restart heating.service")
        machine.wait_until_succeeds("curl -sf ${url}/metrics | grep -qx 'heating_target_celsius{room=\"bedroom\"} 18'")
  '';
}
