# serviceConfig for a unit running slopops, which may run any command without
# asking. A weak sandbox: what it can still reach includes the deploy key.
{
  NoNewPrivileges = true;
  RestrictSUIDSGID = true;
  CapabilityBoundingSet = "";
  PrivateDevices = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  ProtectControlGroups = true;
  ProtectClock = true;
  ProtectHostname = true;
  ProtectProc = "invisible";
  LockPersonality = true;
  RestrictRealtime = true;
  RestrictNamespaces = true;
  SystemCallArchitectures = "native";
  RestrictAddressFamilies = [
    "AF_UNIX"
    "AF_INET"
    "AF_INET6"
  ];
}
