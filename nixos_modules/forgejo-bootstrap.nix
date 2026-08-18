{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.forgejo;
  repos = config.bjackman.forgejoAgentRepos;
  webhook = config.bjackman.forgejoAgentWebhook;
  apiUrl = "http://127.0.0.1:${toString config.bjackman.ports.forgejo.port}/api/v1";
  slopbotKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDjnmpfN+r2BJ6ksEvVpQDmDQaEpk+sV9GVMeqK6/pg1 slopbot@forgejo";
in
{
  options.bjackman.forgejoAgentRepos = lib.mkOption {
    type = with lib.types; listOf str;
    default = [ ];
    description = ''
      Names of repos owned by `brendan` that agents may propose changes to.

      slopbot gets write access so it can open AGit pull requests, master is
      protected so it can't push there directly, and the `agent` label that
      marks a pull request as agent-driven is created.
    '';
  };

  options.bjackman.forgejoAgentWebhook = lib.mkOption {
    type =
      with lib.types;
      nullOr (submodule {
        options = {
          host = lib.mkOption {
            type = str;
            description = "Host running the agent handler.";
          };
          port = lib.mkOption {
            type = port;
            description = "Port the agent handler serves the webhook on.";
          };
        };
      });
    default = null;
    description = ''
      Where to deliver review activity on agent pull requests. Null leaves no
      webhook configured, so agent runs only happen when the handler sweeps.
    '';
  };

  config = lib.mkIf (repos != [ ]) {
    age.secrets = {
      slopbot-forgejo-password = {
        file = ../secrets/slopbot-forgejo-password.age;
        mode = "400";
        owner = cfg.user;
      };
      forgejo-bootstrap-password = {
        file = ../secrets/forgejo-bootstrap-password.age;
        mode = "400";
        owner = cfg.user;
      };
      slopbot-webhook-secret = {
        file = ../secrets/slopbot-webhook-secret.age;
        mode = "400";
        owner = cfg.user;
      };
    };

    # Forgejo will only call public addresses by default, and the handler is on
    # the tailnet.
    services.forgejo.settings.webhook.ALLOWED_HOST_LIST = lib.mkIf (webhook != null) webhook.host;

    # Users and passwords are CLI-managed; collaborators, branch protection and
    # labels are API-only. The API needs an account that can authenticate to it,
    # so there's a dedicated admin with a password from agenix. An access token
    # would be the obvious alternative, but `admin user generate-access-token`
    # can neither replace nor delete one, and the token endpoints that could are
    # basic-auth-only - which brendan can't do with ENABLE_INTERNAL_SIGNIN off.
    systemd.services.forgejo-bootstrap = {
      after = [ "forgejo.service" ];
      requires = [ "forgejo.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [
        config.age.secrets.slopbot-forgejo-password.file
        config.age.secrets.forgejo-bootstrap-password.file
        config.age.secrets.slopbot-webhook-secret.file
      ];
      path = [
        cfg.package
        pkgs.curl
        pkgs.jq
        pkgs.gawk
      ];
      environment = {
        HOME = cfg.stateDir;
        FORGEJO_WORK_DIR = cfg.stateDir;
        FORGEJO_CUSTOM = cfg.customDir;
      };
      script = ''
        bootstrap_pw=$(cat ${config.age.secrets.forgejo-bootstrap-password.path})
        slopbot_pw=$(cat ${config.age.secrets.slopbot-forgejo-password.path})
        slopbot_key=${lib.escapeShellArg slopbotKey}
        ${lib.optionalString (webhook != null) ''
          webhook_url=${lib.escapeShellArg "http://${webhook.host}:${toString webhook.port}/forgejo"}
          webhook_secret=$(cat ${config.age.secrets.slopbot-webhook-secret.path})
        ''}

        resp=$(mktemp)
        trap 'rm -f "$resp"' EXIT

        ensure_user() {
          local name=$1 pw=$2
          shift 2
          if forgejo admin user list | awk -v u="$name" 'NR > 1 && $2 == u { found = 1 } END { exit !found }'; then
            forgejo admin user change-password --username "$name" --password "$pw" --must-change-password=false
          else
            forgejo admin user create --username "$name" --email "$name@invalid.example" \
              --password "$pw" --must-change-password=false "$@"
          fi
        }

        req() {
          local method=$1 path=$2 data=''${3-}
          local args=(-sS -o "$resp" -w '%{http_code}' -u "bootstrap:$bootstrap_pw" -X "$method" "${apiUrl}$path")
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
          echo "unexpected HTTP $got from Forgejo: $(cat "$resp")" >&2
          return 1
        }

        ensure_user bootstrap "$bootstrap_pw" --admin
        ensure_user slopbot "$slopbot_pw"

        for _ in $(seq 60); do
          if [ "$(req GET /version)" = 200 ]; then
            break
          fi
          sleep 1
        done
        expect "$(req GET /version)" 200

        expect "$(req GET /users/slopbot/keys)" 200
        if ! jq -r '.[].key' "$resp" | awk '{ print $2 }' | grep -qxF "$(awk '{ print $2 }' <<<"$slopbot_key")"; then
          expect "$(req POST /admin/users/slopbot/keys \
            "$(jq -n --arg k "$slopbot_key" '{title: "slopbot", key: $k}')")" 201
        fi

        for repo in ${lib.escapeShellArgs repos}; do
          expect "$(req PUT "/repos/brendan/$repo/collaborators/slopbot" '{"permission": "write"}')" 204

          # Everyone but me pushes through a pull request. slopbot has write
          # access because AGit needs it, so this is what stops it landing its
          # own changes.
          protection='{"rule_name": "master", "enable_push": true, "enable_push_whitelist": true, "push_whitelist_usernames": ["brendan"]}'
          if [ "$(req GET "/repos/brendan/$repo/branch_protections/master")" = 404 ]; then
            expect "$(req POST "/repos/brendan/$repo/branch_protections" "$protection")" 201
          else
            expect "$(req PATCH "/repos/brendan/$repo/branch_protections/master" "$protection")" 200
          fi

          expect "$(req GET "/repos/brendan/$repo/labels")" 200
          if ! jq -e '.[] | select(.name == "agent")' "$resp" >/dev/null; then
            expect "$(req POST "/repos/brendan/$repo/labels" \
              '{"name": "agent", "color": "#5319e7", "description": "Comments here drive an agent"}')" 201
          fi

          ${lib.optionalString (webhook != null) ''
            expect "$(req GET "/repos/brendan/$repo/hooks")" 200
            hook_id=$(jq -r --arg url "$webhook_url" '.[] | select(.config.url == $url) | .id' "$resp" | head -1)
            hook=$(jq -n --arg url "$webhook_url" --arg secret "$webhook_secret" \
              '{type: "forgejo", active: true, events: $ARGS.positional,
                config: {url: $url, content_type: "json", secret: $secret}}' \
              --args issue_comment pull_request_comment pull_request_review)
            if [ -z "$hook_id" ]; then
              expect "$(req POST "/repos/brendan/$repo/hooks" "$hook")" 201
            else
              expect "$(req PATCH "/repos/brendan/$repo/hooks/$hook_id" "$hook")" 200
            fi
          ''}
        done
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
      };
    };
  };
}
