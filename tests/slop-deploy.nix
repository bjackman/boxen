# slop-deploy in a VM: the forced command, the sudo rule, the policy and a
# real switch. What it fakes is the build. Each commit of the fixture repository
# names a system that is already in the VM's store, so that nothing has to be
# evaluated inside the VM.
{ lib, pkgs }:
let
  sshKeys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
  repoPath = "/srv/boxen.git";
  git = lib.getExe pkgs.git;
  slopProbe = "${pkgs.bjackman.slop-probe}/bin/slop-probe";
in
pkgs.testers.runNixOSTest (
  { nodes, ... }:
  let
    systemPath = name: nodes.target.slopDeployTest.systems.${name};

    makeFixtureRepo = pkgs.writeShellApplication {
      name = "make-fixture-repo";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.git
      ];
      text = ''
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        git -C "$work" init --quiet --initial-branch=master
        export GIT_AUTHOR_NAME=Brendan GIT_AUTHOR_EMAIL=brendan@example.com
        export GIT_COMMITTER_NAME=Gerrit GIT_COMMITTER_EMAIL=gerrit@example.com

        commit() {
            local when
            when="@$(($(date +%s) - $1 * 86400)) +0000"
            echo "$2" >"$work/toplevel"
            git -C "$work" add toplevel
            GIT_AUTHOR_DATE=$when GIT_COMMITTER_DATE=$when \
                git -C "$work" commit --quiet --allow-empty --message "$3"
        }

        commit 45 ${systemPath "initial"} "target: Initial configuration"
        commit 10 ${systemPath "good"} "target: Keep more journal"
        git -C "$work" branch wip
        commit 0 ${systemPath "broken"} "target: Add frobnicator"
        git -C "$work" checkout --quiet wip
        commit 1 ${systemPath "good"} "target: Try a newer kernel"
        git -C "$work" checkout --quiet master
        git clone --quiet --bare "$work" "$1"
        # It stands in for the repository that everything else fetches from.
        git -C "$1" remote remove origin
      '';
    };
  in
  {
    name = "slop-deploy";

    nodes.target =
      {
        config,
        extendModules,
        pkgs,
        ...
      }:
      let
        moreJournal.services.journald.extraConfig = "SystemMaxUse=1G";
        frobnicator.systemd.services.frobnicator = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.coreutils}/bin/false";
          };
        };
        system = modules: (extendModules { inherit modules; }).config.system.build.toplevel;
      in
      {
        imports = [
          ../nixos_modules/slop-probe.nix
          ../nixos_modules/slop-deploy.nix
        ];

        options.slopDeployTest.systems = lib.mkOption {
          type = with lib.types; attrsOf package;
          description = "The systems the fixture's commits name.";
        };

        config = {
          virtualisation.memorySize = 1024;
          services.openssh.enable = true;
          # Test nodes leave it out unless they have specialisations.
          system.switch.enable = true;
          # The VM boots its kernel directly, and a switch would otherwise try
          # to install GRUB on a disk it can't go on.
          boot.loader.grub.enable = false;

          bjackman.slopProbe.authorizedKey = sshKeys.snakeOilPublicKey;
          bjackman.slopDeploy = {
            authorizedKey = sshKeys.snakeOilPublicKey;
            repoUrl = repoPath;
            build = pkgs.writeShellScript "slop-deploy-fixture-build" ''
              exec ${git} -C "$1" show "$2:toplevel"
            '';
          };

          # Each adds a module to the one before, so that a diff between two of
          # them is what the commit message says. Not specialisations, so that
          # they stay out of the closure of the system the VM boots.
          slopDeployTest.systems = {
            initial = config.system.build.toplevel;
            good = system [ moreJournal ];
            broken = system [
              moreJournal
              frobnicator
            ];
          };
          virtualisation.additionalPaths = [
            config.slopDeployTest.systems.good
            config.slopDeployTest.systems.broken
          ];
        };
      };

    testScript = ''
      import re

      target.wait_for_unit("multi-user.target")
      target.succeed(
          "${lib.getExe makeFixtureRepo} ${repoPath}",
          "install -D -m 600 ${sshKeys.snakeOilPrivateKey} /root/.ssh/id",
          "ssh-keyscan localhost > /root/.ssh/known_hosts",
      )

      def rev(ref: str) -> str:
          return target.succeed(f"${git} -C ${repoPath} rev-parse {ref}").strip()

      tip, recent, old, unmerged = rev("master"), rev("master~1"), rev("master~2"), rev("wip")
      # As Gerrit's is on pizza, owned by the server rather than by root.
      target.succeed("chown -R nobody:nogroup ${repoPath}")

      def probe(user: str, *args: str) -> tuple[int, str]:
          return target.execute(
              f"${slopProbe} --ssh-user={user} --key-file=/root/.ssh/id"
              + " --known-hosts-file=/root/.ssh/known_hosts --hosts=localhost"
              + f" localhost {' '.join(args)} 2>&1"
          )

      def deploy(commit: str) -> tuple[int, str]:
          return probe("slopops", "deploy", f"--rev={commit}")

      def running() -> str:
          return target.succeed("readlink -f /run/current-system").strip()

      initial = running()

      with subtest("Refuses commits outside the policy"):
          for commit, reason in [
              (old, "days old"),
              (unmerged, "is not on master"),
              ("0" * 40, "is not on master"),
          ]:
              status, out = deploy(commit)
              t.assertNotEqual(status, 0, out)
              t.assertIn(reason, out)
          status, out = deploy("master")
          t.assertEqual(status, 111, out)
          t.assertEqual(running(), initial)

      with subtest("Deploys a recent commit"):
          status, out = deploy(recent)
          t.assertEqual(status, 0, out)
          t.assertEqual(running(), "${systemPath "good"}")

      with subtest("Reports a deploy that leaves a unit failed"):
          status, out = deploy(tip)
          t.assertNotEqual(status, 0, out)
          t.assertIn("frobnicator.service", out)
          t.assertEqual(running(), "${systemPath "broken"}")

      with subtest("Rolls back"):
          status, out = deploy(recent)
          t.assertEqual(status, 0, out)
          t.assertEqual(running(), "${systemPath "good"}")

      with subtest("Deploy logs are readable through the probes"):
          status, out = probe("slopbot", "journal", f"--unit=slop-deploy@{recent}.service")
          t.assertEqual(status, 0, out)
          t.assertIn(f"Deployed {recent}", out)

      with subtest("Nothing else can deploy, and the deploy user can do nothing else"):
          status, out = probe("slopbot", "deploy", f"--rev={recent}")
          t.assertEqual(status, 111, out)
          target.fail(f"runuser -u slopbot -- systemctl start slop-deploy@{recent}.service")
          target.fail("runuser -u slopops -- sudo --non-interactive systemctl restart sshd.service")
          allowed = target.succeed("runuser -u slopops -- sudo --non-interactive --list")
          start = re.findall(r"NOPASSWD: (/nix/store/\S+)", allowed)
          t.assertEqual(len(start), 1, allowed)
          t.assertTrue(start[0].endswith("/bin/slop-deploy-start"), allowed)
          for argument in ["master", f"{recent} --force", "'''"]:
              target.fail(f"runuser -u slopops -- sudo --non-interactive {start[0]} {argument}")
    '';
  }
)
