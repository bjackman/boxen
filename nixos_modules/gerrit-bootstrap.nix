{
  pkgs,
  lib,
  config,
  ...
}:
let
  repos = config.bjackman.gerritAgentRepos;
  apiUrl = "http://127.0.0.1:${toString config.bjackman.ports.gerrit.port}";
  fqdn = config.bjackman.iap.services.gerrit.fqdn;
  authHeader = config.services.gerrit.settings.auth.httpHeader;
  admin = "brendan";
  slopbotKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDjnmpfN+r2BJ6ksEvVpQDmDQaEpk+sV9GVMeqK6/pg1 slopbot@forgejo";
in
{
  options.bjackman.gerritAgentRepos = lib.mkOption {
    type = with lib.types; listOf str;
    default = [ ];
    description = ''
      Projects agents may propose changes to. Gerrit's default access rules
      already deny slopbot everything that matters - direct push to a branch,
      voting Code-Review+2 on its own change, and submitting - so this only has
      to create the projects.
    '';
  };

  config = lib.mkIf (repos != [ ]) {
    # Everything here goes through the REST API on loopback, authenticated by
    # the header Gerrit is configured to trust. That's also how the admin
    # account comes into being: the first account to authenticate is made an
    # administrator, so this unit creates it deliberately rather than leaving it
    # to whoever logs in first.
    systemd.services.gerrit-bootstrap = {
      after = [ "gerrit.service" ];
      requires = [ "gerrit.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.curl
        pkgs.gawk
        pkgs.jq
      ];
      script = ''
        cookies=$(mktemp)
        resp=$(mktemp)
        trap 'rm -f "$cookies" "$resp"' EXIT

        for _ in $(seq 60); do
          if curl -sS -o /dev/null "${apiUrl}/"; then
            break
          fi
          sleep 2
        done

        # Gerrit is configured for a TLS-terminating proxy, so it redirects
        # plain requests to https on its own port unless they look like they
        # came through one. These are the headers Caddy sends.
        proxied=(
          -H "${authHeader}: ${admin}"
          -H "X-Forwarded-Proto: https"
          -H "X-Forwarded-Host: ${fqdn}"
        )

        # Logging in creates the account if it doesn't exist. The XSRF token
        # that mutations need isn't set until something loads the UI, so ask
        # for the root as well.
        curl -sS -c "$cookies" -b "$cookies" -o /dev/null \
          "''${proxied[@]}" "${apiUrl}/login/%2F"
        curl -sS -c "$cookies" -b "$cookies" -o /dev/null \
          "''${proxied[@]}" "${apiUrl}/"
        token=$(awk '$6 == "XSRF_TOKEN" { print $7 }' "$cookies")
        if [ -z "$token" ]; then
          echo "no XSRF token: is auth.type still HTTP?" >&2
          exit 1
        fi

        req() {
          local method=$1 path=$2 data=''${3-}
          local args=(-sS -o "$resp" -w '%{http_code}' -c "$cookies" -b "$cookies"
            "''${proxied[@]}" -H "X-Gerrit-Auth: $token"
            -H 'Content-Type: application/json' -X "$method" "${apiUrl}$path")
          if [ -n "$data" ]; then
            args+=(-d "$data")
          fi
          curl "''${args[@]}"
        }

        expect() {
          local got=$1
          shift
          for want in "$@"; do
            if [ "$got" = "$want" ]; then
              return 0
            fi
          done
          echo "unexpected HTTP $got from Gerrit: $(cat "$resp")" >&2
          return 1
        }

        # Creating the account registers the key, the address a push's committer
        # must match, and the Service Users membership that keeps the bot out of
        # my attention set. No password: the agent authenticates to Authelia,
        # and Gerrit only ever sees the header that comes back.
        if [ "$(req GET /a/accounts/slopbot)" = 404 ]; then
          expect "$(req PUT /a/accounts/slopbot "$(jq -n \
            --arg key ${lib.escapeShellArg slopbotKey} \
            '{name: "slopbot", email: "slopbot@yawn.io", ssh_key: $key,
              groups: ["Service Users"]}')")" 201
        fi

        for project in ${lib.escapeShellArgs repos}; do
          if [ "$(req GET "/a/projects/$project")" = 404 ]; then
            expect "$(req PUT "/a/projects/$project" '{"create_empty_commit": true}')" 201
          fi
        done
      '';
      # Runs as root: it only makes HTTP calls to loopback, and Gerrit itself
      # runs under DynamicUser so there is no service account to borrow.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
