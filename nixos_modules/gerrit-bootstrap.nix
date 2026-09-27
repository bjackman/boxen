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
  gerritConfig = ../gerrit_config;
  stateDir = "/var/lib/gerrit-bootstrap";
  keyPath = "${stateDir}/id_ed25519";
  hostKeyPath = "/var/lib/gerrit/etc/ssh_host_ed25519_key.pub";
  sshUrl = "ssh://${admin}@127.0.0.1:${toString config.bjackman.gerritSshPort}";
  slopbotKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDjnmpfN+r2BJ6ksEvVpQDmDQaEpk+sV9GVMeqK6/pg1 slopbot@forgejo";
  ciBotKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFy1m+rbpUHFBGKfEVI1pgMGZtOtqNyQc751D4BIuDCP ci-bot@gerrit";
  ciBot = {
    email = "ci-bot@yawn.io";
    displayName = "CI";
  };
  reviewBot = {
    email = "review-bot@yawn.io";
    displayName = "Review bot";
  };
in
{
  imports = [ ./impermanence.nix ];

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
    # Everything but git goes through the REST API on loopback, authenticated
    # by the header Gerrit is configured to trust. That's also how the admin
    # account comes into being: the first account to authenticate is made an
    # administrator, so this unit creates it deliberately rather than leaving
    # it to whoever logs in first.
    systemd.services.gerrit-bootstrap = {
      after = [ "gerrit.service" ];
      requires = [ "gerrit.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.curl
        pkgs.git
        pkgs.gnused
        pkgs.coreutils
        pkgs.gawk
        pkgs.jq
        pkgs.openssh
      ];
      script = ''
        cookies=$(mktemp)
        resp=$(mktemp)
        keys=$(mktemp)
        known_hosts=$(mktemp)
        trap 'rm -f "$cookies" "$resp" "$keys" "$known_hosts"' EXIT

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

        # Git goes over SSH because Gerrit only serves it over HTTP when
        # download.scheme offers HTTP. The key is registered as mine, which
        # grants nothing that the header doesn't already.
        if [ ! -e ${keyPath} ]; then
          ssh-keygen -q -t ed25519 -N "" -C gerrit-bootstrap -f ${keyPath}
        fi

        # My own keys, so that pushing to a branch and administering over SSH
        # need no separate registration step.
        expect "$(req GET "/a/accounts/${admin}/sshkeys")" 200
        # Gerrit prefixes JSON responses with )]}' to break naive cross-site
        # script inclusion, which jq will not parse.
        tail -c +6 "$resp" > "$keys"
        for key in ${lib.escapeShellArgs adminKeys} "$(cat ${keyPath}.pub)"; do
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
        ${lib.optionalString config.bjackman.reviewBot.enable ''
          # Its key only exists in the secret, which the agent can't read.
          bot_account review-bot ${reviewBot.email} ${lib.escapeShellArg reviewBot.displayName} \
            "$(ssh-keygen -y -f ${config.age.secrets.review-bot-ssh-privkey.path})"
        ''}

        # Voting on a label is granted to a group, never to an account.
        if [ "$(req GET /a/groups/ci)" = 404 ]; then
          expect "$(req PUT /a/groups/ci '{"description": "Accounts that vote Verified."}')" 201
          # Gerrit makes whoever created the group its first member, and this
          # group means "has actually run the checks", which I have not.
          # Overriding a vote by hand is a separate grant, in project.config.
          expect "$(req DELETE "/a/groups/ci/members/${admin}")" 204 404
        fi
        expect "$(req PUT /a/groups/ci/members/ci-bot)" 201 200


        # A project's configuration - its ACLs, its labels and its submit
        # requirements - is a file on refs/meta/config, so it's a file in the
        # repo rather than a translation of one into API calls. Only these
        # projects: All-Projects holds every default, and replacing its config
        # wholesale would drop the lot.
        #
        # The groups file beside it maps each group the config names to a UUID
        # that is generated per instance, so it can't be checked in and is
        # written here instead.
        configure_project() {
          local project=$1 source=$2 work
          work=$(mktemp -d)
          git -C "$work" init -q
          git -C "$work" fetch -q "${sshUrl}/$project" refs/meta/config
          git -C "$work" checkout -q FETCH_HEAD
          cp "$source" "$work/project.config"

          # A rule is "<what> = [<range>] group <name>", and a name may contain
          # spaces, so it runs to the end of the line.
          local names uuid
          names=$(sed -n '/^[[:space:]]*#/d; s/.* group \(.*\)$/\1/p' "$source" | sort -u)
          # Fed in by here-string rather than a pipeline, so that a group that
          # can't be looked up fails the unit instead of writing a groups file
          # with a hole in it.
          {
            printf '# UUID\tGroup Name\n#\n'
            while read -r name; do
              [ -n "$name" ] || continue
              expect "$(req GET "/a/groups/''${name// /+}")" 200
              # Ids are URL-encoded, which matters for the system groups whose
              # UUID is of the form global:Registered-Users.
              uuid=$(tail -c +6 "$resp" | jq -re .id | sed 's/%3A/:/g')
              printf '%s\t%s\n' "$uuid" "$name"
            done <<< "$names"
          } > "$work/groups"

          if git -C "$work" diff --quiet; then
            rm -rf "$work"
            return
          fi
          # Never rewritten when nothing changed: this is the ref that says who
          # may push, so a generation that turns out to be wrong should be one
          # commit to look at rather than one per boot.
          git -C "$work" add project.config groups
          git -C "$work" -c user.name=gerrit-bootstrap -c user.email=${adminUser.email} \
            commit -q -m "Configure $project from the boxen repo"
          git -C "$work" push -q "${sshUrl}/$project" HEAD:refs/meta/config
          rm -rf "$work"
        }

        echo "[127.0.0.1]:${toString config.bjackman.gerritSshPort} $(cat ${hostKeyPath})" > "$known_hosts"
        export GIT_SSH_COMMAND="ssh -i ${keyPath} -o IdentitiesOnly=yes -o UserKnownHostsFile=$known_hosts"

        expect "$(req GET /a/groups/Administrators)" 200
        administrators=$(tail -c +6 "$resp" | jq -r .id)

        for project in ${lib.escapeShellArgs projects}; do
          if [ "$(req GET "/a/projects/$project")" = 404 ]; then
            expect "$(req PUT "/a/projects/$project" "{}")" 201
          fi
          # The one grant that can't come from the file, because it's the grant
          # that permits the push: being an administrator is not enough on its
          # own, refs/meta/config wants an owner who also holds Push. Granting
          # it over REST breaks the circularity, and project.config carries the
          # same rule so that replacing the file doesn't revoke it.
          #
          # Only when it's missing: the endpoint commits to refs/meta/config
          # whether or not the rule is already there, so calling it every boot
          # would rewrite the ref forever.
          expect "$(req GET "/a/projects/$project/access")" 200
          if ! tail -c +6 "$resp" | jq -e --arg group "$administrators" \
            '.local["refs/meta/config"].permissions.push.rules[$group]' >/dev/null; then
            expect "$(req POST "/a/projects/$project/access" "$(jq -n --arg group "$administrators" \
              '{add: {"refs/meta/config": {permissions: {push: {rules: {($group): {action: "ALLOW", force: false}}}}}}}')")" 200
          fi
          configure_project "$project" "${gerritConfig}/$project/project.config"
        done
      '';
      # Runs as root: it only talks to Gerrit on loopback, and Gerrit itself
      # runs under DynamicUser so there is no service account to borrow.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "gerrit-bootstrap";
        StateDirectoryMode = "0700";
      };
    };

    bjackman.impermanence.extraPersistence.directories = [
      {
        directory = stateDir;
        mode = "0700";
        user = "root";
        group = "root";
      }
    ];
  };
}
