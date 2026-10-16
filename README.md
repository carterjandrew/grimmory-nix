# Grimmory for NixOS

<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-with-text.svg">
  <img src="assets/logo-with-text-light.svg" alt="Grimmory" height="80" />
</picture>

<picture>
  <img src="https://icon-icons.com/id/icon/nixos-logo/170910" alt="Nix" height="80" />
</picture>

[![Release](https://img.shields.io/github/v/release/grimmory-tools/grimmory?color=818CF8&logo=github)](https://github.com/grimmory-tools/grimmory/releases)
[![License](https://img.shields.io/github/license/grimmory-tools/grimmory?color=fab005)](LICENSE)
[![Crowdin](https://badges.crowdin.net/grimmory/localized.svg)](https://crowdin.com/project/grimmory)
[![Docker Pulls](https://img.shields.io/docker/pulls/grimmory/grimmory?color=2496ED&logo=docker&logoColor=white)](https://hub.docker.com/r/grimmory/grimmory)
[![Discord](https://img.shields.io/badge/Discord-5865F2?logo=discord&logoColor=white)](https://discord.gg/9YJ7HB4n8T)

[Documentation](https://grimmory.org/docs) · [Usage](#usage)

</div>

[Grimmory](https://github.com/grimmory-tools/grimmory) is a:
> self-hosted digital library for people who take their reading seriously.

[Nix](https://nixos.org/) is a:
> tool that takes a unique approach to package management and system configuration by making builds reproducible, declarative, and reliable.


This flake packages Grimmory and provides a NixOS module. Grimmory serves
its web interface and API from one configurable listener; the module exposes
that listener through `services.grimmory.listenAddress` and
`services.grimmory.port`.

## Usage

Add the flake as an input:

```nix
{
  inputs.grimmory.url = "github:your-name/grimmory-nix";

  outputs = { nixpkgs, grimmory, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        grimmory.nixosModules.default
        {
          services.grimmory = {
            enable = true;
            port = 6060;
            database.passwordFile = "/run/secrets/grimmory-database-password";
          };
        }
      ];
    };
  };
}
```

The default configuration creates a local MariaDB database and listens only on
`127.0.0.1:6060`, suitable for use behind a reverse proxy. Set
`listenAddress = "0.0.0.0"` and `openFirewall = true` to expose Grimmory
directly.

The password file is required for both local and external databases. It is
loaded with systemd credentials rather than copied into the Nix store. With a
secret manager, make sure the file exists before `grimmory.service` starts.

### External database

```nix
services.grimmory = {
  enable = true;
  port = 7777;
  database = {
    createLocally = false;
    host = "database.example.net";
    port = 3306;
    name = "grimmory";
    user = "grimmory";
    passwordFile = "/run/secrets/grimmory-database-password";
  };
};
```

### Storage and additional settings

Application data, the default books directory, and BookDrop live below
`/var/lib/grimmory` by default. Additional library paths must be explicitly
made available to the hardened service:

```nix
services.grimmory = {
  extraLibraryPaths = [ "/srv/books" ];
  environment = {
    TZ = "America/Guatemala";
    API_DOCS_ENABLED = "false";
  };
  environmentFiles = [ "/run/secrets/grimmory-environment" ];
};
```

The module owns listener, storage, and database environment variables; set
those through the typed module options rather than `environment`.

## Development

```console
nix build .#grimmory
nix flake check
```

The package supports `x86_64-linux` and `aarch64-linux`. The NixOS integration
test runs on `x86_64-linux` and verifies local MariaDB provisioning, the web UI,
the health endpoint, restart behavior, and use of a non-default port.
