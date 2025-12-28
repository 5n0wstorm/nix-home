{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.nextcloud;
  homepageCfg = config.fleet.apps.homepage;
  acmeCfg = config.fleet.security.acme;
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

    logging = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Nextcloud logging";
      };

      level = mkOption {
        type = types.enum [0 1 2 3 4];
        default = 2;
        description = "Log level: 0=debug, 1=info, 2=warning, 3=error, 4=fatal";
      };

      type = mkOption {
        type = types.enum ["file" "syslog" "errorlog" "owncloud"];
        default = "file";
        description = "Log type: file=syslog, syslog=system syslog, errorlog=PHP error log, owncloud=Nextcloud's own log format";
      };

      file = mkOption {
        type = types.str;
        default = "/var/log/nextcloud.log";
        description = "Path to log file (only used when type = 'file')";
      };

      rotateSize = mkOption {
        type = types.int;
        default = 104857600; # 100MB
        description = "Maximum log file size in bytes before rotation (only used when type = 'file')";
      };
    };

    php = {
      errorReporting = mkOption {
        type = types.str;
        default = "E_ALL & ~E_NOTICE & ~E_WARNING & ~E_DEPRECATED";
        description = "PHP error reporting level to suppress log noise";
      };

      displayErrors = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to display PHP errors in the browser";
      };

      logErrors = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to log PHP errors";
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
    # NGINX (TLS + limits)
    # --------------------------------------------------------------------------

    # Nextcloud already configures an nginx vhost as part of services.nextcloud.
    # Our fleet "reverseProxy" module is also nginx, so proxying Nextcloud to
    # 127.0.0.1:80 creates an nginx->nginx loop (and can yield 400s/redirects).
    #
    # Instead, attach TLS + request limits directly to Nextcloud's nginx vhost.
    services.nginx.virtualHosts.${cfg.hostname} = mkMerge [
      {
        extraConfig = ''
          proxy_read_timeout 3600s;
          proxy_connect_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      }
      (mkIf acmeCfg.enable {
        sslCertificate = acmeCfg.certPath;
        sslCertificateKey = acmeCfg.keyPath;
        forceSSL = true;
      })
    ];

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

      # Reverse-proxy awareness (prevents login redirect loops behind nginx/TLS).
      # Our fleet reverse proxy terminates TLS and forwards to Nextcloud via HTTP.
      settings = {
        trusted_domains = [cfg.domain];
        trusted_proxies = ["127.0.0.1"];
        overwriteprotocol = "https";
        overwritehost = cfg.domain;
        "overwrite.cli.url" = "https://${cfg.domain}";
      } // optionalAttrs cfg.logging.enable {
        # Logging configuration
        loglevel = cfg.logging.level;
        log_type = cfg.logging.type;
        logfile = cfg.logging.file;
        log_rotate_size = cfg.logging.rotateSize;
      } // {
        # PHP configuration to reduce log noise and suppress notices
        # This addresses issues like "Undefined array key" errors in SystemTagManager
        php_error_reporting = cfg.php.errorReporting;
        php_display_errors = cfg.php.displayErrors;
        php_log_errors = cfg.php.logErrors;
      };

      settings."apps_paths" = mkOverride 0 [
        {
          path = "${config.services.nextcloud.finalPackage}/apps";
          url = "/apps";
          writable = false;
        }
        {
          # NixOS places packaged (Nix) apps here (including services.nextcloud.extraApps).
          # If this path is missing from apps_paths, `occ app:install <name>` will try
          # to download from the app store and fail with messages like:
          #   Could not download app calendar, it was not found on the appstore
          path = "${config.services.nextcloud.finalPackage}/nix-apps";
          url = "/nix-apps";
          writable = false;
        }
        {
          # Writable custom apps directory (kept under the persistent datadir).
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
    ] ++ optional cfg.logging.enable [
      "d /var/log 0755 root root -"
      "f ${cfg.logging.file} 0644 nextcloud nextcloud -"
    ];

    # --------------------------------------------------------------------------
    # WORKAROUND: nixpkgs emits a `store-apps` apps_paths entry
    # --------------------------------------------------------------------------
    #
    # On some nixpkgs revisions, Nextcloud's generated `override.config.php`
    # contains an apps_paths entry pointing at:
    #   ${finalPackage}/store-apps
    # but the directory does not exist in the produced package output, causing
    # Nextcloud to hard-fail at runtime with:
    #   App directory ".../store-apps" not found!
    #
    # `services.nextcloud.settings` cannot remove it because it is merged in
    # afterwards (array_replace_recursive). As a practical workaround, patch the
    # generated file after activation and before php-fpm starts.
    systemd.services.nextcloud-fix-override-config = {
      description = "Patch Nextcloud override.config.php to drop non-existent store-apps apps_paths entry";
      # Important: Nextcloud's initial config.php is created by nextcloud-setup.
      # If setup runs before this patch, it can fail to generate config.php.
      wantedBy = [
        "phpfpm-nextcloud.service"
        "nextcloud-setup.service"
        "nextcloud-update-db.service"
        "nextcloud-cron.service"
      ];
      before = [
        "phpfpm-nextcloud.service"
        "nextcloud-setup.service"
        "nextcloud-update-db.service"
        "nextcloud-cron.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        cfg="${cfg.dataDir}/config/override.config.php"
        if [ ! -f "$cfg" ]; then
          exit 0
        fi

        # Drop any apps_paths entries referencing store-apps.
        # Each entry is on a single line in the generated file.
        ${pkgs.gnused}/bin/sed -i "/store-apps/d" "$cfg"
      '';
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    # Nextcloud runs behind reverse proxy, so no direct firewall access needed
    networking.firewall.allowedTCPPorts = [];
  };
}
