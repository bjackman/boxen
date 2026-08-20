{
  pkgs,
  lib,
  config,
  ...
}:
let
  projects = config.bjackman.gerritProjects;
  apiUrl = "http://127.0.0.1:${toString config.bjackman.ports.gerrit.port}";
  fqdn = config.bjackman.iap.services.gerrit.fqdn;
  authHeader = config.services.gerrit.settings.auth.httpHeader;
  admin = "brendan";
  agent = config.bjackman.homelab.users.slopbot;
  adminUser = config.bjackman.homelab.users.${admin};
  # The same keys the hosts authorise, so pushing to a branch and administering
  # over SSH needs no separate registration step.
  adminKeys = config.users.users.${admin}.openssh.authorizedKeys.keys;
  slopbotKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDjnmpfN+r2BJ6ksEvVpQDmDQaEpk+sV9GVMeqK6/pg1 slopbot@forgejo";
  ciBotKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFy1m+rbpUHFBGKfEVI1pgMGZtOtqNyQc751D4BIuDCP ci-bot@gerrit";
  ciBot = {
    email = "ci-bot@yawn.io";
    displayName = "CI";
  };
in
{
  options.bjackman.gerritSshPort = lib.mkOption {
    type = lib.types.port;
    readOnly = true;
    # Not from bjackman.ports: those are allocated by position, so adding or
    # removing any service shifts them - harmless for something reached through
    # Caddy, and not for a port that ends up in every clone's remote URL.
    # 29418 is Gerrit's conventional port.
    default = 29418;
    description = "Port Gerrit serves git and its command interface on.";
  };
  options.bjackman.gerritProjects = lib.mkOption {
    type = with lib.types; listOf str;
    default = [ ];
    description = ''
      Projects to create, and to grant myself push on. Nothing here is about
      the agent: Gerrit's default rules already deny slopbot everything that
      matters - direct push to a branch, voting Code-Review+2 on its own
      change, and submitting - whichever projects exist.
    '';
  };

  config = lib.mkIf (projects != [ ]) {
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
          -H "Remote-Email: ${adminUser.email}"
          -H "Remote-Name: ${adminUser.displayName}"
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
            -X "$method" "${apiUrl}$path")
          # Only with a body: Gerrit rejects a JSON content type and nothing to
          # parse, which is how several of its endpoints are called.
          if [ -n "$data" ]; then
            args+=(-H 'Content-Type: application/json' -d "$data")
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
        #
        # The identity headers are the ones Authelia would send, so an account
        # that also has an Authelia identity ends up agreeing with users.json.
        bot_account() {
          local user=$1 email=$2 name=$3 key=$4
          if [ "$(req GET "/a/accounts/$user")" = 404 ]; then
            local bot_cookies
            bot_cookies=$(mktemp)
            curl -sS -c "$bot_cookies" -b "$bot_cookies" -o /dev/null \
              -H "${authHeader}: $user" \
              -H "Remote-Email: $email" \
              -H "Remote-Name: $name" \
              -H "X-Forwarded-Proto: https" -H "X-Forwarded-Host: ${fqdn}" \
              "${apiUrl}/login/%2F"
            rm -f "$bot_cookies"
            expect "$(req GET "/a/accounts/$user")" 200
          fi

          # Keeps the bot out of my attention set.
          expect "$(req PUT "/a/groups/Service%20Users/members/$user")" 201 200

          register_email "$user" "$email"

          expect "$(req GET "/a/accounts/$user/sshkeys")" 200
          tail -c +6 "$resp" > "$keys"
          local encoded
          encoded=$(echo "$key" | awk '{ print $2 }')
          if ! jq -e --arg key "$encoded" 'any(.[]; .encoded_key == $key)' "$keys" >/dev/null; then
            expect "$(curl -sS -o "$resp" -w '%{http_code}' -c "$cookies" -b "$cookies" \
              "''${proxied[@]}" -H "X-Gerrit-Auth: $token" -H 'Content-Type: text/plain' \
              -X POST --data-binary "$key" "${apiUrl}/a/accounts/$user/sshkeys")" 201
          fi
        }

        # An address is only taken from the header when the account is created,
        # so registering it explicitly covers accounts that predate the header
        # being configured. Without one, a push is refused unless the account
        # happens to hold "forge committer".
        register_email() {
          expect "$(req PUT "/a/accounts/$1/emails/''${2/@/%40}" \
            '{"no_confirmation": true, "preferred": true}')" 201 409
        }

        register_email ${admin} ${adminUser.email}
        bot_account slopbot ${agent.email} ${lib.escapeShellArg agent.displayName} \
          ${lib.escapeShellArg slopbotKey}
        # ci-bot votes Verified and does nothing else. Unlike slopbot it never
        # speaks REST, so it has no Authelia identity and its address and name
        # are written here rather than in users.json - an entry there would mint
        # an Authelia login that nothing would ever use.
        bot_account ci-bot ${ciBot.email} ${lib.escapeShellArg ciBot.displayName} \
          ${lib.escapeShellArg ciBotKey}

        # Voting on a label is granted to a group, never to an account.
        if [ "$(req GET /a/groups/ci)" = 404 ]; then
          expect "$(req PUT /a/groups/ci '{"description": "Accounts that vote Verified."}')" 201
        fi
        expect "$(req PUT /a/groups/ci/members/ci-bot)" 201 200


        # Gerrit's defaults let an administrator create a branch but not push
        # commits to one: the mainline is only meant to advance by submitting a
        # change. That's right for slopbot and wrong for me, and an import of
        # existing history needs it.
        expect "$(req GET /a/groups/Administrators)" 200
        administrators=$(tail -c +6 "$resp" | jq -r .id)
        for project in ${lib.escapeShellArgs projects}; do
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
