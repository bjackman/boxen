# This is a configuration file that the `agenix` CLI (provided by this repo's
# devShell) reads if you are running it from this directory. It informs how
# files are encrypted.
let
  chungito = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaakNfELyvjLLCRwH2U/yQ35HkEW+hEShAD7sn0mCmH brendan@chungito";
  brendan-thinkpad = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDMi2QRJG+/nM2ekysSUT6h1uNlSmo31ubSK28DrGVezoh2MaPXz6XWMpJtDvr9FHHOVpsCTFxFQ9A7DTqgFy0NxwTHJhK5bevxaWYRkv43H8EMR9pJXYMDAtj7Gk+NNK5ssGZm2P+cTl9r5QZOm0PaVUUeoA/KxbVCNEenOCHM5Lv2RrXGufJL1ukRL6I83fl3ilfgEOz2RBG3QQGahVqYfZq/mfo07U0vad9RX7y6I+8Ap8XSCe33yfO0338yPf0A69p90xtpiJyYyAtVN+0KT552wpMtPjprXt5mrpYDLZvW6vBu0mFGkmDoz3ekb+MmWJVlE9f1VyjHpmA1bRn18gQ73egrGlVWvPHpAJ3gl5bKtc30Md/M4u3tyauDoAnqOs/FAqvClDz1Yav+5Ck5umnDSXXWH/WToX9AUsevjLQq1uB2QJU6oYeEIpEHWC4dUtgPXrX/SYDSGmqA5xOqboyn39oIcNWXTOrqnes52bBlOW3/zCX51EIx/tiG3LU= brendan@brendan-thinkpad";
  all-personal = [
    chungito
    brendan-thinkpad
  ];
in
{
  # This is the password for the 'admin' user, configured via the PiKVM UI or
  # something I can't remember.
  "eadbald-pikvm-password.age".publicKeys = all-personal;
}
