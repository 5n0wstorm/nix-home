{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.nextcloud;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.nextcloud = {
    enable = mkEnableOption "Nextcloud file sync and sharing platform";

    domain = mkOption {
      type = types.str;
      default = "nextcloud.local";
      description = "Domain name for Nextcloud";
    };

    hostname = mkOption {
      type = types.str;
      default = cfg.domain;
      description = "Hostname for Nextcloud (defaults to domain)";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/nextcloud";
      description = "Data directory for Nextcloud";
    };

    database = {
      type = mkOption {
        type = types.enum ["mysql" "pgsql"];
        default = "mysql";
        description = "Database backend for Nextcloud";
      };

      mysql = {
        useFleetMysql = mkOption {
          type = types.bool;
          default = false;
          description = "Use connection info from fleet.apps.mysql.connections.nextcloud (requires a mysql databaseRequest)";
        };

        host = mkOption {
          type = types.str;
          default = "localhost";
          description = "MySQL host (ignored if useFleetMysql = true)";
        };

        port = mkOption {
          type = types.port;
          default = 3306;
          description = "MySQL port (ignored if useFleetMysql = true)";
        };

        database = mkOption {
          type = types.str;
          default = "nextcloud";
          description = "MySQL database name (ignored if useFleetMysql = true)";
        };

        user = mkOption {
          type = types.str;
          default = "nextcloud";
          description = "MySQL user (ignored if useFleetMysql = true)";
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to MySQL password file (ignored if useFleetMysql = true)";
        };
      };
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
        default = "Nextcloud";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "File sync and sharing";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-nextcloud";
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
    # ASSERTIONS
    # --------------------------------------------------------------------------

    assertions = [
      {
        assertion = !cfg.database.mysql.useFleetMysql || (attrByPath ["fleet" "apps" "mysql" "connections" "nextcloud"] null config != null);
        message = "fleet.apps.nextcloud.database.mysql.useFleetMysql is true, but fleet.apps.mysql.connections.nextcloud is not available. Ensure a database request exists in fleet.apps.mysql.databaseRequests.";
      }
      {
        assertion = cfg.database.type != "mysql" || cfg.database.mysql.useFleetMysql || cfg.database.mysql.passwordFile != null;
        message = "fleet.apps.nextcloud.database.mysql.passwordFile must be set when useFleetMysql is false";
      }
    ];

    # --------------------------------------------------------------------------
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.nextcloud = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.nextcloud = {
      port = 80;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.websockets" = "true";
        "fleet.reverse-proxy.extra-config" = ''
          client_max_body_size 10G;
          proxy_read_timeout 3600s;
          proxy_connect_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
        # Nextcloud handles its own authentication
        "fleet.authelia.bypass" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # DATABASE CONFIGURATION
    # --------------------------------------------------------------------------

    services.nextcloud = let
      mysqlConn = attrByPath ["fleet" "apps" "mysql" "connections" "nextcloud"] null config;
      mysqlFromFleet = cfg.database.type == "mysql" && cfg.database.mysql.useFleetMysql && mysqlConn != null;
      mysqlHost =
        if mysqlFromFleet
        then mysqlConn.host
        else cfg.database.mysql.host;
      mysqlPort =
        if mysqlFromFleet
        then mysqlConn.port
        else cfg.database.mysql.port;
      mysqlDatabase =
        if mysqlFromFleet
        then mysqlConn.database
        else cfg.database.mysql.database;
      mysqlUser =
        if mysqlFromFleet
        then mysqlConn.user
        else cfg.database.mysql.user;
      mysqlPasswordFile =
        if mysqlFromFleet
        then mysqlConn.passwordFile
        else cfg.database.mysql.passwordFile;
      nextcloudPkg = pkgs.nextcloud32;
    in {
      enable = true;
      package = nextcloudPkg;
      hostName = cfg.hostname;
      datadir = cfg.dataDir;
      config = {
        adminuser = "admin";
        adminpassFile = "/run/secrets/nextcloud/admin-password";
        dbtype = cfg.database.type;
        dbhost = "${mysqlHost}:${toString mysqlPort}";
        dbname = mysqlDatabase;
        dbuser = mysqlUser;
        dbpassFile = mysqlPasswordFile;
      };

      settings.apps_paths = mkForce [
        {
          path = "${config.services.nextcloud.package}/apps";
          url = "/apps";
          writable = false;
        }
        {
          path = "${cfg.dataDir}/apps";
          url = "/custom_apps";
          writable = true;
        }
      ];

      https = true;
      maxUploadSize = "10G";

      # Install basic apps
      extraApps = {
        inherit (nextcloudPkg.packages.apps) contacts calendar tasks;
      };
      extraAppsEnable = true;
    };

    # --------------------------------------------------------------------------
    # SOPS SECRET FOR ADMIN PASSWORD
    # --------------------------------------------------------------------------

    # Note: Add this to your galadriel configuration.nix sops.secrets section:
    # "nextcloud/admin-password" = {
    #   owner = "nextcloud";
    #   group = "nextcloud";
    #   mode = "0400";
    # };

    # --------------------------------------------------------------------------
    # DATA DIRECTORY
    # --------------------------------------------------------------------------

    # Note: Add this to your galadriel configuration.nix systemd.tmpfiles.rules:
    # "d ${cfg.dataDir} 0750 nextcloud nextcloud -"

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 nextcloud nextcloud -"
      "d ${cfg.dataDir}/apps 0750 nextcloud nextcloud -"
    ];

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    # Nextcloud runs behind reverse proxy, so no direct firewall access needed
    networking.firewall.allowedTCPPorts = [];
  };
}
