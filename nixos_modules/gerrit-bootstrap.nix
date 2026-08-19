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
  # The same keys the hosts authorise, so pushing to a branch and administering
  # over SSH needs no separate registration step.
  adminKeys = config.users.users.${admin}.openssh.authorizedKeys.keys;
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
        pkgs.coreutils
        pkgs.gawk
        pkgs.jq
      ];
      script = ''
        cookies=$(mktemp)
        resp=$(mktemp)
        keys=$(mktemp)
        trap 'rm -f "$cookies" "$resp" "$keys"' EXIT

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

        # My own keys, so that pushing to a branch and administering over SSH
        # need no separate registration step.
        expect "$(req GET "/a/accounts/${admin}/sshkeys")" 200
        # Gerrit prefixes JSON responses with )]}' to break naive cross-site
        # script inclusion, which jq will not parse.
        tail -c +6 "$resp" > "$keys"
        for key in ${lib.escapeShellArgs adminKeys}; do
          encoded=$(echo "$key" | awk '{ print $2 }')
          if ! jq -e --arg key "$encoded" 'any(.[]; .encoded_key == $key)' "$keys" >/dev/null; then
            expect "$(curl -sS -o "$resp" -w '%{http_code}' -c "$cookies" -b "$cookies" \
              "''${proxied[@]}" -H "X-Gerrit-Auth: $token" -H 'Content-Type: text/plain' \
              -X POST --data-binary "$key" "${apiUrl}/a/accounts/${admin}/sshkeys")" 201
          fi
        done

        # Created by logging in as it, the way my own account comes to exist.
        # An account made through the API gets a "username:" external ID but not
        # the "gerrit:" one that header authentication looks up, so the two
        # never link: the first login tries to create a second account, collides
        # on the username, and fails for good.
        if [ "$(req GET /a/accounts/slopbot)" = 404 ]; then
          slopbot_cookies=$(mktemp)
          curl -sS -c "$slopbot_cookies" -b "$slopbot_cookies" -o /dev/null \
            -H "${authHeader}: slopbot" \
            -H "X-Forwarded-Proto: https" -H "X-Forwarded-Host: ${fqdn}" \
            "${apiUrl}/login/%2F"
          rm -f "$slopbot_cookies"
          expect "$(req GET /a/accounts/slopbot)" 200
        fi

        # The rest is set on whichever account that produced.
        expect "$(req PUT "/a/accounts/slopbot/name" '{"name": "slopbot"}')" 200
        # The address a push's committer has to match.
        expect "$(req PUT "/a/accounts/slopbot/emails/slopbot%40yawn.io" \
          '{"no_confirmation": true, "preferred": true}')" 201 409
        # Keeps the bot out of my attention set.
        expect "$(req PUT "/a/groups/Service%20Users/members/slopbot")" 201 200

        expect "$(req GET /a/accounts/slopbot/sshkeys)" 200
        tail -c +6 "$resp" > "$keys"
        slopbot_key_encoded=$(echo ${lib.escapeShellArg slopbotKey} | awk '{ print $2 }')
        if ! jq -e --arg key "$slopbot_key_encoded" 'any(.[]; .encoded_key == $key)' "$keys" >/dev/null; then
          expect "$(curl -sS -o "$resp" -w '%{http_code}' -c "$cookies" -b "$cookies" \
            "''${proxied[@]}" -H "X-Gerrit-Auth: $token" -H 'Content-Type: text/plain' \
            -X POST --data-binary ${lib.escapeShellArg slopbotKey} \
            "${apiUrl}/a/accounts/slopbot/sshkeys")" 201
        fi


        # Gerrit's defaults let an administrator create a branch but not push
        # commits to one: the mainline is only meant to advance by submitting a
        # change. That's right for slopbot and wrong for me, and an import of
        # existing history needs it.
        expect "$(req GET /a/groups/Administrators)" 200
        administrators=$(tail -c +6 "$resp" | jq -r .id)
        for project in ${lib.escapeShellArgs repos}; do
          if [ "$(req GET "/a/projects/$project")" = 404 ]; then
            expect "$(req PUT "/a/projects/$project" "{}")" 201
          fi
          expect "$(req POST "/a/projects/$project/access" "$(jq -n --arg group "$administrators" \
            '{add: {"refs/heads/*": {permissions: {push: {rules: {($group): {action: "ALLOW", force: false}}}}}}}')")" 200
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
