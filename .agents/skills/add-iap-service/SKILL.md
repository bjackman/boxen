______________________________________________________________________

## name: add-iap-service description: Add a new IAP service using the bjackman.iap.services and bjackman.ports modules for automated port allocation and IAP reverse proxying. Use when creating a new self-hosted web service in this repository.

# Adding a New NixOS Service

When setting up a new service in this repository, it should be integrated with the custom port allocation and Identity-Aware Proxy (IAP) logic to ensure consistent port mapping and secure reverse proxying.

## Port Allocation Logic

The repository uses a unique automatic port allocation trick defined in `nixos_modules/ports.nix`.
Instead of manually hardcoding a port number for each new service, you can declare an empty attribute under `bjackman.ports` for your service.

Under the hood, Nix evaluates all services declared in `bjackman.ports`, sorts them alphabetically by name, and assigns a unique port starting at 9000 (`9000 + index`).

To allocate a port, add this line:

```nix
bjackman.ports.<service_name> = { };
```

Then, you can access the assigned port number via:

```nix
config.bjackman.ports.<service_name>.port
```

## Adding the Service

Here is the standard pattern for adding a new service, such as a web application. You should typically create a new `.nix` file in `nixos_modules/` or adapt an existing one:

```nix
{ pkgs, config, ... }:
{
  imports = [
    ./ports.nix
    ./iap.nix
  ];

  # 1. Allocate a unique port for this service automatically
  bjackman.ports.<service_name> = { };

  # 2. Expose the service via the IAP (Identity-Aware Proxy)
  bjackman.iap.services.<service_name> = {
    port = config.bjackman.ports.<service_name>.port;
    # Optional: Restrict access to specific users
    # allowedUsers = [ "brendan" ];
  };

  # 3. Configure the actual NixOS service
  services.<service_name> = {
    enable = true;
    # Tell the service to listen on the automatically allocated port
    listenPort = config.bjackman.ports.<service_name>.port;
    # ... other service-specific settings
  };
}
```

## Summary of Steps

1. Create a module for your new service (e.g., `nixos_modules/<service_name>.nix`).
1. Make sure you import `./ports.nix` and `./iap.nix` if needed.
1. Define `bjackman.ports.<service_name> = { };`.
1. Configure `bjackman.iap.services.<service_name>` with the allocated port to route external traffic to it.
1. Set up the native `services.<service_name>` settings using `config.bjackman.ports.<service_name>.port` as its listen port.
