# SSH host public keys for the machines in this repo. They are agenix
# recipients (see secrets.nix) and also the known-hosts entries anything
# connecting to these machines non-interactively needs, so they live in one
# place rather than being copied into both.
{
  chungito = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBTTgMTKXqjE6Vdd5mYMqtU3CxHdTFLVW4TNg3K5dfpo root@chungito";
  fw13 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHVBFKZzXD+YUcB83N+FfIHFH2rQpk060e1OjEWZMp59 root@nixos";
  norte = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwxzu2JNI7hdrKWlmqjkwNLRf7kMEcSlxE3nKUrbEp6 root@norte";
  pizza = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmiVXunDkdw9EBJtfPshYvR3od5p00vbL9MqlaJZgGf root@pizza";
  slopbox = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEtq1hx4Z4uL/Hqjuz/d56uxFCpSuOAHiFOs8v0yMUaF root@slopbox";
}
