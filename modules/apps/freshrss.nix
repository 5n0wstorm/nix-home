{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.apps.freshrss;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.freshrss = {
    enable = mkEnableOption "FreshRSS RSS aggregator";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for FreshRSS web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "freshrss.local";
      description = "Domain name for FreshRSS";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/freshrss";
      description = "Data directory for FreshRSS configuration";
    };

    timezone = mkOption {
      type = types.str;
      default = "Etc/UTC";
      description = "Timezone for FreshRSS container";
    };

    user = mkOption {
      type = types.str;
      default = "freshrss";
      description = "User to run FreshRSS container as";
    };

    group = mkOption {
      type = types.str;
      default = "freshrss";
      description = "Group to run FreshRSS container as";
    };

    # Homepage dashboard integration
    homepage = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Register this service with the homepage dashboard";
      };

      name = mkOption {
        type = types.str;
        default = "FreshRSS";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "RSS feed aggregator";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-rss";
        description = "Icon for homepage (mdi-*, si-*, or URL)";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Apps";
        description = "Category on the homepage dashboard";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.freshrss = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "http://${cfg.domain}:${toString cfg.port}";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # USER AND GROUP SETUP
    # --------------------------------------------------------------------------

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.${cfg.group} = {};

    # --------------------------------------------------------------------------
    # DATA DIRECTORY SETUP
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
    ];

    # --------------------------------------------------------------------------
    # FRESHRSS CONTAINER
    # --------------------------------------------------------------------------

    virtualisation.oci-containers.containers.freshrss = {
      image = "lscr.io/linuxserver/freshrss:latest";

      ports = [
        "${toString cfg.port}:80"
      ];

      environment = {
        PUID = toString config.users.users.${cfg.user}.uid;
        PGID = toString config.users.groups.${cfg.group}.gid;
        TZ = cfg.timezone;
      };

      volumes = [
        "${cfg.dataDir}:/config"
      ];

      extraOptions = [
        "--pull=always"
      ];
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];

    # --------------------------------------------------------------------------
    # SYSTEMD SERVICE DEPENDENCIES
    # --------------------------------------------------------------------------

    systemd.services."podman-freshrss" = {
      requires = ["podman.service"];
      after = ["podman.service"];
    };
  };
}
