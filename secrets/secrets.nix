# This is a configuration file that the `agenix` CLI (provided by this repo's
# devShell) reads if you are running it from this directory. It informs how
# files are encrypted.
let
  chungito = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaakNfELyvjLLCRwH2U/yQ35HkEW+hEShAD7sn0mCmH brendan@chungito";
  chungito-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBTTgMTKXqjE6Vdd5mYMqtU3CxHdTFLVW4TNg3K5dfpo root@chungito";
  brendan-thinkpad = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDMi2QRJG+/nM2ekysSUT6h1uNlSmo31ubSK28DrGVezoh2MaPXz6XWMpJtDvr9FHHOVpsCTFxFQ9A7DTqgFy0NxwTHJhK5bevxaWYRkv43H8EMR9pJXYMDAtj7Gk+NNK5ssGZm2P+cTl9r5QZOm0PaVUUeoA/KxbVCNEenOCHM5Lv2RrXGufJL1ukRL6I83fl3ilfgEOz2RBG3QQGahVqYfZq/mfo07U0vad9RX7y6I+8Ap8XSCe33yfO0338yPf0A69p90xtpiJyYyAtVN+0KT552wpMtPjprXt5mrpYDLZvW6vBu0mFGkmDoz3ekb+MmWJVlE9f1VyjHpmA1bRn18gQ73egrGlVWvPHpAJ3gl5bKtc30Md/M4u3tyauDoAnqOs/FAqvClDz1Yav+5Ck5umnDSXXWH/WToX9AUsevjLQq1uB2QJU6oYeEIpEHWC4dUtgPXrX/SYDSGmqA5xOqboyn39oIcNWXTOrqnes52bBlOW3/zCX51EIx/tiG3LU= brendan@brendan-thinkpad";
  norte-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAZNWHZreyeHnOpGcduRfsTTKOeDrAHIix8JQpr9GC3v root@norte";
  personal-hosts = [
    chungito-host
    norte-host
  ];
  all-personal = personal-hosts ++ [
    chungito
    brendan-thinkpad
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
  # Password for Jellyfin admin account, hashed as per
  # https://github.com/Sveske-Juice/declarative-jellyfin/tree/main?tab=readme-ov-file#generate-user-password-hash
  "jellyfin-admin-password-hash.age".publicKeys = all-personal;
  # Contains a JSON object of the form { "rpc-password": "{asfjdsakl.H" }.
  # The value is the hash of password for the Transmission daemon. To generate
  # the hash, I wrote it into the settings.json manually and then restarted the
  # service. The transmission edits the settings file lol.
  "transmission-rpc-password.json.age".publicKeys = all-personal;
  # This is a weak password so encrypt it instead of just checking in the salted
  # hash. This shouldn't be decrypted with user keys only host keys.
  # Content generated with mkpasswd -m yescrypt -R 9
  "weak-local-password-hash.age".publicKeys = personal-hosts;
}
