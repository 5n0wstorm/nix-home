{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.networking.tailscale;

  # Shared tailscale up flags. --reset belongs only in the recovery oneshot so
  # nixos-switch does not pass it twice (breaks tailscale up) via tailscaled +
  # fleet-tailscale-network-recovery running in the same activation.
  tailscaleUpFlags =
    [
      "--login-server=${cfg.loginServer}"
      "--accept-routes=${
        if cfg.acceptRoutes
        then "true"
        else "false"
      }"
      "--accept-dns=${
        if cfg.acceptDns
        then "true"
        else "false"
      }"
    ]
    ++ (optionals (cfg.hostname != null) ["--hostname=${cfg.hostname}"])
    ++ (optionals (cfg.advertiseRoutes != []) [
      "--advertise-routes=${concatStringsSep "," cfg.advertiseRoutes}"
    ])
    ++ (filter (f: f != "--reset") cfg.extraUpFlags);
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.networking.tailscale = {
    enable = mkEnableOption "Tailscale mesh client (Headscale-compatible)";

    loginServer = mkOption {
      type = types.str;
      default = "https://headscale.sn0wstorm.com";
      description = "Coordination server URL (Headscale or Tailscale control plane)";
    };

    authKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a pre-authentication key file (recommended via sops-nix)";
    };

    hostname = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Hostname to register on the tailnet (defaults to networking.hostName)";
    };

    advertiseRoutes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Subnets to advertise to the tailnet (requires approval on the control server)";
      example = ["192.168.178.0/24"];
    };

    acceptRoutes = mkOption {
      type = types.bool;
      default = true;
      description = "Accept subnet routes from other tailnet nodes";
    };

    acceptDns = mkOption {
      type = types.bool;
      default = true;
      description = "Accept MagicDNS configuration from the control server";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open UDP 41641 for direct WireGuard connections";
    };

    useRoutingFeatures = mkOption {
      type = types.enum ["none" "client" "server" "both"];
      default =
        if cfg.advertiseRoutes != []
        then "both"
        else "client";
      description = "Enable IP forwarding and routing features in tailscaled";
    };

    extraUpFlags = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional flags passed to `tailscale up`";
    };

    extraDaemonFlags = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional flags passed to tailscaled";
    };

    networkRecovery = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Periodically re-apply `tailscale up` and restart tailscaled when the
        backend is not running. Helps nodes recover after internet outages
        without a manual intervention.
      '';
    };

    networkRecoveryInterval = mkOption {
      type = types.str;
      default = "5min";
      description = "How often to run the Tailscale network recovery check";
    };

    healthCheckPeer = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Optional tailnet IPv4 of a peer that must stay reachable (e.g. Proxmox at
        100.64.0.1). When ping fails while the backend reports Running, tailscaled
        is restarted to refresh NAT mappings after a home WAN IP change.
      '';
      example = "100.64.0.1";
    };

    detectWanIpChange = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Track the STUN-discovered public IPv4 and restart tailscaled when it
        changes. Needed on NAT hosts where the FritzBox/ISP rotates the WAN
        address but the LAN interface (and NetworkManager) stay unchanged.
      '';
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    environment.etc."tailscale/tailscaled.conf".text = builtins.toJSON {
      ServerURL = cfg.loginServer;
    };

    networking = mkIf cfg.openFirewall {
      firewall.allowedUDPPorts = [41641];
    };

    services.tailscale = {
      enable = true;
      authKeyFile = cfg.authKeyFile;
      useRoutingFeatures = cfg.useRoutingFeatures;

      extraDaemonFlags = cfg.extraDaemonFlags;

      extraUpFlags = tailscaleUpFlags;
    };

    # Avoid stop-then-start during nixos-rebuild switch. Stopping tailscaled
    # drops subnet routes and can kill the SSH session used by Colmena (e.g. from
    # elrond over the tailnet). A single restart is enough for config updates.
    systemd.services.tailscaled.stopIfChanged = false;

    # Subnet routers need forwarding enabled on the host.
    boot.kernel.sysctl = mkIf (cfg.advertiseRoutes != []) {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # ==========================================================================
    # NETWORK OUTAGE RECOVERY
    # ==========================================================================

    systemd.services.fleet-tailscale-network-recovery = mkIf cfg.networkRecovery {
      description = "Recover Tailscale mesh after network outages";
      after = ["tailscaled.service" "network-online.target" "sysinit-reactivation.target"];
      wants = ["network-online.target"];
      restartIfChanged = false;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        # Must not fail nixos-switch / nh rebuild activation.
        SuccessExitStatus = "0 1 2 143";
        # Skip when switch-to-configuration is still reactivating services.
        ExecCondition = "! ${pkgs.systemd}/bin/systemctl is-active --quiet sysinit-reactivation.target";
      };

      path = with pkgs; [tailscale jq coreutils systemd];

      script = let
        upCommand = "tailscale up ${concatStringsSep " " (tailscaleUpFlags ++ ["--reset"])}";
      in ''
        set -o pipefail

        restart_tailscaled_if_ready() {
          case "$(systemctl show tailscaled.service -p ActiveState --value 2>/dev/null || echo unknown)" in
            active)
              systemctl restart tailscaled.service || true
              sleep 5
              ;;
            activating|reloading)
              echo "tailscaled still starting, skipping restart"
              ;;
            *)
              systemctl start tailscaled.service || true
              sleep 3
              ;;
          esac
        }

        STATE_DIR=/var/lib/tailscale
        PUBLIC_IP_FILE="$STATE_DIR/last-public-ipv4"
        mkdir -p "$STATE_DIR"

        if ! systemctl is-active --quiet tailscaled.service; then
          echo "tailscaled inactive, starting"
          restart_tailscaled_if_ready
        fi

        ${optionalString cfg.detectWanIpChange ''
          CURRENT_IP=$(${pkgs.tailscale}/bin/tailscale netcheck 2>/dev/null \
            | ${pkgs.gnugrep}/bin/grep -oE 'IPv4: yes, [0-9.]+' \
            | ${pkgs.gnugrep}/bin/grep -oE '[0-9.]+' \
            | tail -1 || true)
          if [ -n "''${CURRENT_IP:-}" ] && [ -f "$PUBLIC_IP_FILE" ]; then
            LAST_IP=$(cat "$PUBLIC_IP_FILE")
            if [ "$CURRENT_IP" != "$LAST_IP" ]; then
              echo "Public IPv4 changed ($LAST_IP -> $CURRENT_IP), restarting tailscaled"
              restart_tailscaled_if_ready
            fi
          fi
          if [ -n "''${CURRENT_IP:-}" ]; then
            echo "$CURRENT_IP" > "$PUBLIC_IP_FILE"
          fi
        ''}

        state=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState // "Unknown"' || echo "Unknown")
        if [ "$state" != "Running" ]; then
          echo "Tailscale backend state is $state, restarting tailscaled"
          restart_tailscaled_if_ready
        fi

        ${optionalString (cfg.healthCheckPeer != null) ''
          if [ "$state" = "Running" ]; then
            if ! ${pkgs.tailscale}/bin/tailscale ping -c 1 ${cfg.healthCheckPeer} >/dev/null 2>&1; then
              echo "Mesh peer ${cfg.healthCheckPeer} unreachable, restarting tailscaled"
              restart_tailscaled_if_ready
            fi
          fi
        ''}

        ${optionalString (cfg.authKeyFile != null) ''
          if [ -f "${cfg.authKeyFile}" ]; then
            AUTH_KEY=$(tr -d '[:space:]' < "${cfg.authKeyFile}")
            ${upCommand} --auth-key="$AUTH_KEY" || ${upCommand} || echo "warn: tailscale up failed; timer will retry"
          else
            ${upCommand} || echo "warn: tailscale up failed; timer will retry"
          fi
        ''}
        ${optionalString (cfg.authKeyFile == null) ''
          ${upCommand} || echo "warn: tailscale up failed; timer will retry"
        ''}

        exit 0
      '';
    };

    systemd.timers.fleet-tailscale-network-recovery = mkIf cfg.networkRecovery {
      description = "Periodic Tailscale mesh recovery timer";
      wantedBy = ["timers.target"];

      timerConfig = {
        # Do not use OnBootSec: when the timer is first enabled during nixos-switch
        # (often >3min after boot), systemd runs the overdue job immediately and can
        # fail activation if headscale re-auth is not ready yet.
        OnActiveSec = "2min";
        OnUnitActiveSec = cfg.networkRecoveryInterval;
        AccuracySec = "30s";
      };

      unitConfig = {
        Unit = "fleet-tailscale-network-recovery.service";
      };
    };
  };
}
