{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.cloudflare-ddns;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.cloudflare-ddns = {
    enable = mkEnableOption "Cloudflare Dynamic DNS client";

    apiTokenFile = mkOption {
      type = types.path;
      description = "Path to file containing Cloudflare API token with DNS edit permissions";
    };

    zoneIdFile = mkOption {
      type = types.path;
      description = "Path to file containing Cloudflare zone ID for the domain";
    };

    recordName = mkOption {
      type = types.str;
      description = "DNS record name to update (e.g., subdomain.example.com)";
    };

    recordType = mkOption {
      type = types.enum ["A" "AAAA"];
      default = "A";
      description = "DNS record type (A for IPv4, AAAA for IPv6)";
    };

    interval = mkOption {
      type = types.str;
      default = "5min";
      description = "How often to check and update DNS record";
    };

    user = mkOption {
      type = types.str;
      default = "cloudflare-ddns";
      description = "User to run Cloudflare DDNS service as";
    };

    group = mkOption {
      type = types.str;
      default = "cloudflare-ddns";
      description = "Group to run Cloudflare DDNS service as";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # USER AND GROUP SETUP
    # --------------------------------------------------------------------------

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
    };

    users.groups.${cfg.group} = {};

    # --------------------------------------------------------------------------
    # CLOUDFLARE DDNS SERVICE
    # --------------------------------------------------------------------------

    systemd.services.cloudflare-ddns = {
      description = "Cloudflare Dynamic DNS Updater";
      after = ["network.target"];
      wants = ["network.target"];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${pkgs.cloudflare-dynamic-dns}/bin/cloudflare-dynamic-dns --api-token-file ${cfg.apiTokenFile} --zone-id-file ${cfg.zoneIdFile} --record-name ${cfg.recordName} --record-type ${cfg.recordType}";
        RemainAfterExit = false;
      };
    };

    # --------------------------------------------------------------------------
    # SYSTEMD TIMER FOR PERIODIC UPDATES
    # --------------------------------------------------------------------------

    systemd.timers.cloudflare-ddns = {
      description = "Timer for Cloudflare Dynamic DNS updates";
      wantedBy = ["timers.target"];

      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
    };
  };
}
