# See ../arr/deploy.nix for more interesting comments.
{ pkgs, self }:
pkgs.writeShellApplication {
  name = "deploy-slopbox-tf";
  runtimeInputs = with pkgs; [ opentofu ];
  runtimeEnv =
    let
      systemBuild = self.nixosConfigurations.slopbox.config.system.build;
    in
    {
      TF_VAR_nixos_image_data = "${systemBuild.qemuImage}/nixos.qcow2";
      TF_VAR_nixos_image_metadata = "${systemBuild.metadata}/tarball/${systemBuild.metadata.fileName}.tar.xz";
    };
  text = ''
    cd "$HOME_MANAGER_CONFIG_CHECKOUT/tf/slopbox"

    TF_VAR_nproc="$(nproc)"
    export TF_VAR_nproc

    # Hack to map host UIDs into the guest, assuming we can hardcode guest UIDs
    # and that host UIDs are at least stable.
    TF_VAR_idmap="$(printf "uid %d 1000\ngid %d 100" "$(id -u)" "$(id -g)")"
    export TF_VAR_idmap

    tofu apply
  '';
}
