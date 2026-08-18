{
  writeShellApplication,
  curl,
  git,
  jq,
  forgejoUrl ? "https://forgejo.home.yawn.io",
  owner ? "brendan",
  passwordFile ? "/run/agenix/slopbot-forgejo-password",
}:
writeShellApplication {
  name = "slop-pr";
  runtimeInputs = [
    curl
    git
    jq
  ];
  text = ''
    forgejo_url=${forgejoUrl}
    owner=${owner}
    password_file=${passwordFile}
  ''
  + builtins.readFile ./slop-pr.sh;
}
