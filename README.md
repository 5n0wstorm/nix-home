# NixOS Fleet Management

This is a starter template for a setup similar to how I manage my own home servers using NixOS + Colmena.

You can use this as a starting point for your own setup.

## Getting started

You need Nix installed on your machine first. If you don't have it, grab it from nixos.org or use the https://determinate.systems/ installer (has some QoL improvements).

If you use direnv (and you should), there's a `.envrc` file that will automatically load the development shell when you enter the directory. Otherwise run `nix develop` manually.

First thing you need is some servers running NixOS. Could be VMs, could be old laptops, whatever. Get them installed and grab their IP addresses.

Edit `hosts.nix` and put your servers in there. Change the IPs and usernames to match your setup. The tags are just for organizing things - you can deploy to all servers with a certain tag.

Each server gets its own directory under `hosts/`. Copy one of the existing ones and modify it. The `hardware-configuration.nix` file comes from running `nixos-generate-config` on the target machine (or just scp'ing it from /etc/nixos/hardware-configuration.nix from the target).

Once you have that sorted, run `nix develop` to get into the development shell, then `colmena apply` to deploy everything.

## How it works

The `modules/` directory contains reusable pieces for different services. Want to run Prometheus? Import the module and set `fleet.monitoring.prometheus.enable = true`. Same pattern for everything else.

All the servers import `hosts/common.nix` which sets up SSH keys, basic security, and monitoring. Individual servers add whatever services they need on top of that.

The reverse proxy on the galadriel server routes traffic to services running on different machines. Self-signed certificates handle TLS so you don't get browser warnings.

## Commands

Deploy everything: `colmena apply`

Deploy one server: `colmena apply --on servername`

Deploy servers with a tag: `colmena apply --on @web`

Run commands on servers: `colmena exec --on servername -- systemctl status nginx`

Build without deploying: `colmena build`

## Adding services

Look at the existing modules to see how they work. Most follow the same pattern: define some options, implement the service when enabled. Import the module in your server config and enable it.

The fleet namespace keeps things organized. Everything lives under `fleet.category.service` like `fleet.monitoring.grafana` or `fleet.dev.gitea`.

As mentioned in the video, AI can do wonders for this.

## Notes

Make sure your SSH key is in `hosts/common.nix` or you won't be able to deploy.

If services aren't accessible, check the firewall settings. Nothing is open by default.

As a quick hack, add the reverse proxy domains to your `/etc/hosts` file so they resolve properly. But better to set up proper DNS.

This setup assumes you're semi-comfortable with NixOS. If you're new to NixOS and flakes, check out the book: https://nixos-and-flakes.thiscute.world/

The monitoring stack will start collecting metrics immediately. Grafana runs on port 3000 of your galadriel server (or whatever you call your main one).


## Resources

- Check out [VimJoyer](https://www.youtube.com/@vimjoyer) for all of the Nix videos
- [NixOS + Flakes book](https://nixos-and-flakes.thiscute.world/)
- [Colmena](https://github.com/zhaofengli/colmena)
