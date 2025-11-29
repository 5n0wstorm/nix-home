{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.system.motd;

  # Collect all enabled fleet services for status display
  # This builds a list of systemd service names to monitor
  fleetServices = let
    # Media services
    mediaServices =
      (optional (config.fleet.media.jellyfin.enable or false) "jellyfin")
      ++ (optional (config.fleet.media.sonarr.enable or false) "sonarr")
      ++ (optional (config.fleet.media.radarr.enable or false) "radarr")
      ++ (optional (config.fleet.media.lidarr.enable or false) "lidarr")
      ++ (optional (config.fleet.media.readarr.enable or false) "readarr")
      ++ (optional (config.fleet.media.prowlarr.enable or false) "prowlarr")
      ++ (optional (config.fleet.media.bazarr.enable or false) "bazarr")
      ++ (optional (config.fleet.media.overseerr.enable or false) "overseerr")
      ++ (optional (config.fleet.media.qbittorrent.enable or false) "qbittorrent")
      ++ (optional (config.fleet.media.transmission.enable or false) "transmission")
      ++ (optional (config.fleet.media.sabnzbd.enable or false) "sabnzbd")
      ++ (optional (config.fleet.media.navidrome.enable or false) "navidrome");

    # App services
    appServices =
      (optional (config.fleet.apps.vaultwarden.enable or false) "vaultwarden")
      ++ (optional (config.fleet.apps.freshrss.enable or false) "podman-freshrss")
      ++ (optional (config.fleet.apps.homepage.enable or false) "homepage-dashboard");

    # Dev services
    devServices =
      (optional (config.fleet.dev.jenkins.enable or false) "jenkins")
      ++ (optional (config.fleet.dev.gitea.enable or false) "gitea");

    # Monitoring services
    monitoringServices =
      (optional (config.fleet.monitoring.prometheus.enable or false) "prometheus")
      ++ (optional (config.fleet.monitoring.grafana.enable or false) "grafana")
      ++ (optional (config.fleet.monitoring.nodeExporter.enable or false) "prometheus-node-exporter");

    # Infrastructure services
    infraServices =
      (optional (config.fleet.networking.reverseProxy.enable or false) "nginx")
      ++ (optional (config.fleet.apps.homepage.enableGlances or false) "glances");
  in
    mediaServices ++ appServices ++ devServices ++ monitoringServices ++ infraServices ++ cfg.extraServices;

  motdScript = pkgs.writeShellScriptBin "motd" ''
    #! /usr/bin/env bash
    source /etc/os-release

    # Catppuccin Latte colors for terminal
    RED="\e[38;2;210;15;57m"
    GREEN="\e[38;2;64;160;43m"
    YELLOW="\e[38;2;223;142;29m"
    BLUE="\e[38;2;30;102;245m"
    MAUVE="\e[38;2;136;57;239m"
    TEAL="\e[38;2;23;146;153m"
    TEXT="\e[38;2;76;79;105m"
    SUBTEXT="\e[38;2;92;95;119m"
    BOLD="\e[1m"
    RESET="\e[0m"

    # System info
    LOAD1=$(cat /proc/loadavg | awk '{print $1}')
    LOAD5=$(cat /proc/loadavg | awk '{print $2}')
    LOAD15=$(cat /proc/loadavg | awk '{print $3}')
    MEMORY=$(free -m | awk 'NR==2{printf "%s/%sMB (%.1f%%)", $3,$2,$3*100/$2}')
    DISK=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
    PROCS=$(ps aux | wc -l)

    # Uptime calculation
    uptime_sec=$(cat /proc/uptime | cut -f1 -d.)
    upDays=$((uptime_sec/60/60/24))
    upHours=$((uptime_sec/60/60%24))
    upMins=$((uptime_sec/60%60))

    if [ $upDays -gt 0 ]; then
      UPTIME="$upDays days, $upHours hrs, $upMins mins"
    elif [ $upHours -gt 0 ]; then
      UPTIME="$upHours hrs, $upMins mins"
    else
      UPTIME="$upMins mins"
    fi

    # Time-based greeting
    HOUR=$(date +"%H")
    if [ $HOUR -lt 12 ] && [ $HOUR -ge 0 ]; then
      GREETING="Good morning"
    elif [ $HOUR -lt 17 ] && [ $HOUR -ge 12 ]; then
      GREETING="Good afternoon"
    else
      GREETING="Good evening"
    fi

    # Header
    echo ""
    printf "$MAUVE$BOLD"
    echo "  ╭─────────────────────────────────────────────────────────────╮"
    printf "  │%63s│\n" ""
    printf "  │  %-59s │\n" "🏠 Welcome to $(hostname)"
    printf "  │  %-59s │\n" "$GREETING!"
    printf "  │%63s│\n" ""
    echo "  ╰─────────────────────────────────────────────────────────────╯"
    printf "$RESET"
    echo ""

    # System Information
    printf "$BLUE$BOLD  ━━━ System Information ━━━$RESET\n"
    echo ""
    printf "$TEAL  %-20s$RESET %s\n" "  Hostname" "$(hostname)"
    printf "$TEAL  %-20s$RESET %s\n" "  OS" "$PRETTY_NAME"
    printf "$TEAL  %-20s$RESET %s\n" "  Kernel" "$(uname -r)"
    printf "$TEAL  %-20s$RESET %s\n" "  Uptime" "$UPTIME"
    echo ""

    # Network Information
    printf "$BLUE$BOLD  ━━━ Network ━━━$RESET\n"
    echo ""
    ${concatStringsSep "\n" (map (iface: ''
      if ip link show ${iface} &>/dev/null; then
        IPV4=$(ip -4 addr show ${iface} 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [ -n "$IPV4" ]; then
          printf "$TEAL  %-20s$RESET %s\n" "  ${iface}" "$IPV4"
        fi
      fi
    '') cfg.networkInterfaces)}
    # Auto-detect primary interface if no specific ones configured
    ${optionalString (cfg.networkInterfaces == []) ''
      NETDEV=$(ip -o route get 8.8.8.8 2>/dev/null | cut -f 5 -d " ")
      if [ -n "$NETDEV" ]; then
        IPV4=$(ip -4 addr show $NETDEV 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        printf "$TEAL  %-20s$RESET %s\n" "  $NETDEV" "$IPV4"
      fi
    ''}
    echo ""

    # Resource Usage
    printf "$BLUE$BOLD  ━━━ Resources ━━━$RESET\n"
    echo ""
    printf "$TEAL  %-20s$RESET %s\n" "  CPU Load" "$LOAD1, $LOAD5, $LOAD15 (1, 5, 15 min)"
    printf "$TEAL  %-20s$RESET %s\n" "  Memory" "$MEMORY"
    printf "$TEAL  %-20s$RESET %s\n" "  Disk (/)" "$DISK"
    printf "$TEAL  %-20s$RESET %s\n" "  Processes" "$PROCS"
    echo ""

    ${optionalString (fleetServices != []) ''
      # Service Status
      printf "$BLUE$BOLD  ━━━ Fleet Services ━━━$RESET\n"
      echo ""

      get_service_status() {
        local svc="$1"
        local status=$(systemctl is-active "$svc" 2>/dev/null)

        case "$status" in
          active)
            printf "$GREEN  ● $RESET%-45s $GREEN[active]$RESET\n" "$svc"
            ;;
          failed)
            printf "$RED  ● $RESET%-45s $RED[failed]$RESET\n" "$svc"
            ;;
          inactive)
            printf "$YELLOW  ○ $RESET%-45s $YELLOW[inactive]$RESET\n" "$svc"
            ;;
          *)
            printf "$SUBTEXT  ○ $RESET%-45s $SUBTEXT[unknown]$RESET\n" "$svc"
            ;;
        esac
      }

      ${concatStringsSep "\n" (map (svc: "get_service_status ${svc}") fleetServices)}
      echo ""
    ''}

    # Footer
    printf "$SUBTEXT  Last login: $(last -1 -R $USER 2>/dev/null | head -1 | awk '{print $3, $4, $5, $6}')$RESET\n"
    echo ""
  '';
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.system.motd = {
    enable = mkEnableOption "Fleet MOTD (Message of the Day)";

    networkInterfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Network interfaces to display. Empty list auto-detects primary interface.";
      example = ["eth0" "ens18"];
    };

    extraServices = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional systemd services to monitor";
      example = ["docker" "podman"];
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # Install the MOTD script
    environment.systemPackages = [motdScript];

    # Disable the default NixOS MOTD (empty string disables it)
    users.motd = "";

    # Configure PAM to not show the default MOTD (we use our own via profile.local)
    security.pam.services.login.showMotd = mkForce false;
    security.pam.services.sshd.showMotd = mkForce false;

    # Use our custom MOTD via profile
    environment.etc."profile.local".text = ''
      # Show Fleet MOTD on interactive login
      if [[ $- == *i* ]] && [[ -z "$MOTD_SHOWN" ]]; then
        export MOTD_SHOWN=1
        motd
      fi
    '';
  };
}

