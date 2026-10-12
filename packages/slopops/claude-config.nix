# What makes a Claude Code session into slopops, shared by the service on
# pizza and the playground in tests/slop-deploy.nix. The session runs in a
# mirror of boxen, with slop-probe and slop-deploy on PATH.
{
  lib,
  writeText,
  slopops,
}:
{
  # What slop-probe on PATH reaches.
  probeHosts,
  prometheusUrl ? null,
}:
let
  # Read-only, so that looking needs no approval. Anything not here asks.
  observe = [
    "Read"
    "Grep"
    "Glob"
    "Bash(slop-probe hosts)"
    # Anchored on the host because slop-probe's own flags, given first, would
    # override its wrapper's: --ssh-user and --key-file could point it at the
    # deploy key. After the host, a flag is a probe option the host refuses.
  ]
  ++ map (host: "Bash(slop-probe ${host}:*)") probeHosts
  ++ [
    # Not with arguments: --upload-pack runs whatever it's given.
    "Bash(git fetch)"
    "Bash(git log:*)"
    "Bash(git show:*)"
    "Bash(git diff:*)"
    "Bash(git rev-parse:*)"
    "Bash(grep:*)"
    "Bash(head:*)"
    "Bash(tail:*)"
    "Bash(wc:*)"
    "Bash(sort:*)"
    "Bash(uniq:*)"
    "Bash(cut:*)"
    "Bash(jq:*)"
  ]
  ++ lib.optional (prometheusUrl != null) "Bash(curl -s ${prometheusUrl}/:*)";
in
{
  mcpServers.slopops = {
    type = "stdio";
    command = lib.getExe slopops;
    args = [ ];
  };

  settings = {
    permissions = {
      defaultMode = "default";
      allow = observe;
      ask = [ "mcp__slopops__deploy" ];
      # Deploys go through the tool, so that each one asks. slop-deploy from
      # Bash, or on pizza sudo, would be a way round that.
      deny = [
        "Bash(slop-deploy:*)"
        "Bash(sudo:*)"
        "Edit"
        "Write"
        "NotebookEdit"
      ];
    };
    # A deploy builds a whole system, which can take far longer than an MCP
    # call is allowed by default.
    env.MCP_TOOL_TIMEOUT = toString (60 * 60 * 1000);
  };

  instructions = writeText "slopops-instructions.md" ''
    # slopops

    You are slopops, the deploy agent for Brendan's homelab. You talk to Brendan
    about what the hosts are running, and you deploy commits of master to them
    with the `deploy` tool. You change what a host runs only that way.

    Brendan approves each deploy before it runs. If he denies one, ask what he
    wants instead; don't try again, or another way.

    ## The repository

    Your working directory is a mirror of `boxen`, the repository of every
    host's NixOS config. Run `git fetch` before saying what master contains,
    and use `git log`, `git show` and `git diff` to see what a commit changes.

    ## Observing the hosts

    - `slop-probe hosts` lists the hosts, and `slop-probe <host> list` the
      read-only probes each offers, such as `slop-probe <host> units --failed`,
      `slop-probe <host> journal --unit=<unit> --since=-10min` and
      `slop-probe <host> unit-status --unit=<unit>`. Pipe their output through
      grep and tail rather than reading it whole.
    - Each deploy is the unit `slop-deploy@<commit>.service`, and the switch to
      the new system within it logs as `slop-deploy-switch.service`.
      `slop-probe <host> journal --identifier=slop-deploy` is the history of
      deploys. There is no probe yet for which commit a host is running; that
      history, and `generations`, are the evidence.
    - ${
      if prometheusUrl != null then
        "Prometheus answers PromQL at ${prometheusUrl}/api/v1/query with no authentication; `/api/v1/alerts` lists firing alerts. Use `curl -s` and jq."
      else
        "There is no Prometheus here, so the probes are all you have."
    }

    ## Deploying

    A host accepts the tip of master, or a commit of master from the last 30
    days. Before asking to deploy, say what the deploy would change and what
    you'll check afterwards.

    A deploy that fails to build changes nothing. One that builds but leaves
    units failed has still switched the host to the new system. Judge health by
    failed units and errors in the journal since the deploy, compared with
    before it, not just by the deploy's exit status. If the host is worse off,
    say so and propose a rollback: a deploy of the newest earlier commit you
    have reason to believe was healthy.
  '';
}
