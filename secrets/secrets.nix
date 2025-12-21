# This is a configuration file that the `agenix` CLI (provided by this repo's
# devShell) reads if you are running it from this directory. It informs how
# files are encrypted.
let
  chungito = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaakNfELyvjLLCRwH2U/yQ35HkEW+hEShAD7sn0mCmH brendan@chungito";
  chungito-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBTTgMTKXqjE6Vdd5mYMqtU3CxHdTFLVW4TNg3K5dfpo root@chungito";
  pizza-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINLKxbIzWQL1j/BybSg/MOOl/XP/+LE78GwdFL6ul+Xo root@pizza";
  all-personal = [
    chungito
    chungito-host
    pizza-host
  ];
  # This key was originally from a Google corp laptop. I no longer have that
  # laptop but it also ended up on lots of other machines too.
  jackmanb-zrh = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLVpV3PnFV5AW4G0aizNgoVu0Wtn3A3arUEJHaEsxy3iFgvvENBcYb+I00HRnYV4FZX1EGD0Fh6lIJcm9YUCm2EKkv9V/mMfV5xaiKcKGZYOLLpaIZw8J3tsuc+iIrl/8Qk1++l6pYIgOCpAgRAY1MxSD/Syg7rZMKiIH2/3CAzzjQej3SCf0Wc2I2/Sv1YUUhNxKGkMi7P4lG8R2erRG8DuPsglEhHW0ua3Hkygy3lfBO9j32JdOXB6+xswWOljiUwnVMt4AbBrZPxn/29BlS/olEgdfxt+jBNM33h9ofKwM+h5oGXomNedgr9qQVha4xj+dbqD7YB/lB/9HMjd1X jackmanb@jackmanb.zrh.corp.google.com";
  all = all-personal ++ [ jackmanb-zrh ];
in
{
  # This is the password for the 'admin' user, configured via the PiKVM UI or
  # something I can't remember.
  "eadbald-pikvm-password.age".publicKeys = all;
  # Contains a JSON object of the form { "rpc-password": "{asfjdsakl.H" }.
  # The value is the hash of password for the Transmission daemon. To generate
  # the hash, I wrote it into the settings.json manually and then restarted the
  # service. The transmission edits the settings file lol.
  "transmission-rpc-password.json.age".publicKeys = all-personal;
  # This is a weak password so encrypt it instead of just checking in the salted
  # hash. Ideally I'd prefer to limit this to only being available to
  # chungito-host. However unfortunately agenix just has a single rekey
  # procedure that applies to all secrets, which means if there's a secret in
  # here that your current SSH key can't decrypt, the process fails.
  # I can't be bothered to figure out how to modularise the secrets just now
  # so, fuck it, anyone can decrypt this shit. (At least on devices I own).
  "weak-local-password-hash.age".publicKeys = all-personal;
}
