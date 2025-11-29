# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a NixOS fleet management repository using Colmena for deploying and managing multiple servers. The architecture follows a modular design:

### Core Components

- **flake.nix**: Main entry point defining inputs, development shell, and Colmena hive configuration
- **hosts.nix**: Single source of truth for all host definitions (IPs, users, tags, descriptions)
- **hosts/**: Individual host configurations importing from common.nix and modules
- **modules/**: Reusable NixOS modules organized by functionality

### Module Structure

The fleet uses a custom module system under the `fleet.*` namespace:
- `fleet.monitoring.*`: Prometheus, Grafana, Node Exporter
- `fleet.dev.*`: Jenkins, Gitea
- `fleet.networking.*`: Reverse proxy with TLS
- `fleet.security.*`: Certificate management (ACME/Let's Encrypt only)

### Host Architecture

All hosts share common configuration via `hosts/common.nix` which includes SSH keys, user management, basic security, and Node Exporter. Individual hosts import specific modules based on their role.

## Development Commands

### Environment Setup
```bash
# Enter development shell with Colmena tools
nix develop
```

### Fleet Management
```bash
# Build all hosts
colmena build

# Deploy to all hosts
colmena apply

# Deploy to specific host
colmena apply --on hostname

# Deploy to hosts with specific tag
colmena apply --on @tag-name

# Execute command on host
colmena exec --on hostname -- command

# Execute command on all hosts
colmena exec -- command
```

### Module Development

When adding new modules:
1. Create under `modules/` following the existing structure
2. Use the `fleet.*` namespace for options
3. Follow the pattern: options definition, implementation with `mkIf cfg.enable`
4. Import in relevant host configurations

### Host Management

To add a new host:
1. Add entry to `hosts.nix` with IP, user, tags, description
2. Create `hosts/hostname/` directory with `configuration.nix` and `hardware-configuration.nix`
3. Add to `colmenaHive` in `flake.nix`

## Key Files

- `flake.nix:19`: Host definitions imported from hosts.nix
- `flake.nix:45-96`: Colmena hive configuration with deployment settings
- `hosts/common.nix:81`: Fleet monitoring enablement
- `modules/monitoring/prometheus.nix:32-36`: Node exporter targets configuration
