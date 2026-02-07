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
      default = "/data/nextcloud/data";
      description = "Data directory for Nextcloud user files";
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

    previews = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable preview generation for files";
      };

      providers = mkOption {
        type = types.listOf types.str;
        default = [
          "OC\\Preview\\PNG"
          "OC\\Preview\\JPEG"
          "OC\\Preview\\GIF"
          "OC\\Preview\\BMP"
          "OC\\Preview\\XBitmap"
          "OC\\Preview\\Krita"
          "OC\\Preview\\WebP"
          "OC\\Preview\\MarkDown"
          "OC\\Preview\\TXT"
          "OC\\Preview\\OpenDocument"
        ];
        description = "List of enabled preview providers";
      };

      videoProviders = mkOption {
        type = types.listOf types.str;
        default = [
          # Nextcloud uses a single provider for video previews (requires ffmpeg).
          "OC\\Preview\\Movie"
        ];
        description = "List of enabled video preview providers";
      };

      maxX = mkOption {
        type = types.int;
        default = 2048;
        description = "Maximum width of previews";
      };

      maxY = mkOption {
        type = types.int;
        default = 2048;
        description = "Maximum height of previews";
      };
    };

    mail = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SMTP mail configuration";
      };

      smtpmode = mkOption {
        type = types.enum ["smtp" "sendmail" "qmail"];
        default = "smtp";
        description = "Mail sending mode";
      };

      smtpsecure = mkOption {
        type = types.enum ["ssl" "tls" ""];
        default = "tls";
        description = "SMTP encryption: ssl, tls, or empty for none";
      };

      smtphost = mkOption {
        type = types.str;
        default = "mail.sn0wstorm.com";
        description = "SMTP server hostname";
      };

      smtpport = mkOption {
        type = types.port;
        default = 587;
        description = "SMTP server port";
      };

      smtpauthtype = mkOption {
        type = types.enum ["LOGIN" "PLAIN" "NTLM" "CRAM-MD5"];
        default = "LOGIN";
        description = "SMTP authentication type";
      };

      smtpname = mkOption {
        type = types.str;
        default = "";
        description = "SMTP authentication username";
      };

      smtppasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing SMTP password";
      };

      fromAddress = mkOption {
        type = types.str;
        default = "nextcloud@sn0wstorm.com";
        description = "From address for sent emails";
      };

      domain = mkOption {
        type = types.str;
        default = "sn0wstorm.com";
        description = "Domain for email addresses";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable (let
    settingsJsonPath = (pkgs.formats.json {}).generate "nextcloud-settings.json" config.services.nextcloud.settings;
  in {
    # --------------------------------------------------------------------------
    # SYSTEM PACKAGES FOR PREVIEWS
    # --------------------------------------------------------------------------

    # Video previews require ffmpeg
    environment.systemPackages = mkIf cfg.previews.enable (
      with pkgs; [ffmpeg]
    );

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
    # CLOSURE: ensure nextcloud-settings.json is deployed
    # --------------------------------------------------------------------------
    # The nextcloud module bakes the path to nextcloud-settings.json into the PHP
    # config. When building remotely (e.g. Colmena from another host), that path
    # can be missing on the target, causing "decoding generated settings file ...
    # failed". Referencing the same derivation here pulls it into the system
    # closure so it is present on deploy.
    environment.etc."nextcloud-settings.json".source = settingsJsonPath;

    # Force the settings JSON path into nextcloud-setup's closure (unit references it).
    systemd.services.nextcloud-setup.environment."NIXOS_NEXTCLOUD_SETTINGS_JSON" = settingsJsonPath;

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
      home = "/var/lib/nextcloud"; # Config directory
      datadir = "/var/lib/nextcloud";
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
      settings =
        {
          trusted_domains = [cfg.domain];
          trusted_proxies = ["127.0.0.1"];
          overwriteprotocol = "https";
          overwritehost = cfg.domain;
          "overwrite.cli.url" = "https://${cfg.domain}";
          # User data directory (files). Keep Nextcloud config/state under /var/lib.
          datadirectory = cfg.dataDir;
        }
        // optionalAttrs cfg.logging.enable {
          # Logging configuration
          loglevel = cfg.logging.level;
          log_type = cfg.logging.type;
          logfile = cfg.logging.file;
          log_rotate_size = cfg.logging.rotateSize;
        }
        // optionalAttrs cfg.previews.enable {
          # Preview configuration
          enabledPreviewProviders = cfg.previews.providers ++ cfg.previews.videoProviders;
          preview_max_x = cfg.previews.maxX;
          preview_max_y = cfg.previews.maxY;
        }
        // optionalAttrs cfg.mail.enable {
          # Mail/SMTP configuration
          mail_smtpmode = cfg.mail.smtpmode;
          mail_smtpsecure = cfg.mail.smtpsecure;
          mail_smtphost = cfg.mail.smtphost;
          mail_smtpport = cfg.mail.smtpport;
          mail_smtpauthtype = cfg.mail.smtpauthtype;
          mail_smtpname = cfg.mail.smtpname;
          mail_from_address = cfg.mail.fromAddress;
          mail_domain = cfg.mail.domain;
        }
        // optionalAttrs (cfg.mail.enable && cfg.mail.smtppasswordFile != null) {
          # Must be a string for JSON settings file; path types can break decoding
          mail_smtppassword = toString cfg.mail.smtppasswordFile;
        }
        // {
          # PHP configuration to reduce log noise and suppress notices
          # This addresses issues like "Undefined array key" errors in SystemTagManager
          php_error_reporting = cfg.php.errorReporting;
          php_display_errors = cfg.php.displayErrors;
          php_log_errors = cfg.php.logErrors;

          # Apps paths configuration. All path values must be strings so the generated
          # nextcloud-settings.json is valid and decodable by PHP (path types can cause
          # "decoding generated settings file ... failed").
          "apps_paths" = [
            {
              path = "${toString config.services.nextcloud.finalPackage}/apps";
              url = "/apps";
              writable = false;
            }
            {
              # NixOS places packaged (Nix) apps here (including services.nextcloud.extraApps).
              # If this path is missing from apps_paths, `occ app:install <name>` will try
              # to download from the app store and fail with messages like:
              #   Could not download app calendar, it was not found on the appstore
              path = "${toString config.services.nextcloud.finalPackage}/nix-apps";
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
        };

      https = true;
      maxUploadSize = "10G";

      # Install basic apps
      extraApps = {
        inherit (nextcloudPkg.packages.apps) contacts calendar tasks previewgenerator memories;
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

    systemd.tmpfiles.rules =
      [
        # Config directory (Nextcloud installation)
        "d /var/lib/nextcloud 0750 nextcloud nextcloud -"
        # Data directory (user files)
        "d /data/nextcloud 0750 nextcloud nextcloud -"
        "d ${cfg.dataDir} 0750 nextcloud nextcloud -"
        # Custom apps directory (referenced by settings.apps_paths)
        "d ${cfg.dataDir}/apps 0750 nextcloud nextcloud -"
      ]
      ++ optionals cfg.logging.enable [
        "f ${cfg.logging.file} 0644 nextcloud nextcloud -"
      ];

    systemd.services.nextcloud-migrate-config-dir = {
      description = "Migrate Nextcloud config dir from /data/nextcloud/config to /var/lib/nextcloud/config";
      wantedBy = [
        "nextcloud-setup.service"
        "phpfpm-nextcloud.service"
        "nextcloud-cron.service"
        "nextcloud-update-db.service"
      ];
      before = [
        "nextcloud-setup.service"
        "phpfpm-nextcloud.service"
        "nextcloud-cron.service"
        "nextcloud-update-db.service"
      ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        src="/data/nextcloud/config"
        dst="/var/lib/nextcloud/config"

        # If config already exists at the new location, do nothing.
        if [ -f "$dst/config.php" ]; then
          exit 0
        fi

        # If old config exists, copy it over preserving perms.
        if [ -f "$src/config.php" ]; then
          mkdir -p "/var/lib/nextcloud"
          ${pkgs.coreutils}/bin/cp -a "$src" "/var/lib/nextcloud/"
          ${pkgs.coreutils}/bin/chown -R nextcloud:nextcloud "/var/lib/nextcloud/config"
        fi
      '';
    };

    # --------------------------------------------------------------------------
    # WORKAROUND: nixpkgs store-apps + stale nextcloud-settings.json path
    # --------------------------------------------------------------------------
    #
    # 1) On some nixpkgs revisions, override.config.php contains an apps_paths
    #    entry for ${finalPackage}/store-apps which does not exist, causing
    #    "App directory .../store-apps not found!". We drop that line.
    #
    # 2) The path to nextcloud-settings.json is baked in at build time. After
    #    a remote deploy the override config in /var/lib can reference an old
    #    store path that is not on the target ("decoding ... failed"). Replace
    #    any nextcloud-settings.json path with the path from our etc symlink
    #    so the file that exists is used.
    systemd.services.nextcloud-fix-override-config = {
      description = "Patch Nextcloud override.config.php (store-apps, settings path)";
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

        cfg="/var/lib/nextcloud/config/override.config.php"
        if [ ! -f "$cfg" ]; then
          exit 0
        fi

        # Drop any apps_paths entries referencing store-apps.
        ${pkgs.gnused}/bin/sed -i "/store-apps/d" "$cfg"

        # If the override config references a nextcloud-settings.json path that
        # does not exist (e.g. stale path after remote deploy), replace it with
        # the path from our /etc symlink so decoding succeeds.
        if [ -e /etc/nextcloud-settings.json ]; then
          good_path="$(${pkgs.coreutils}/bin/readlink -f /etc/nextcloud-settings.json)"
          if [ -n "$good_path" ] && [ -f "$good_path" ]; then
            ${pkgs.gnused}/bin/sed -i "s|/nix/store/[a-z0-9]*-nextcloud-settings\.json|$good_path|g" "$cfg"
          fi
        fi
      '';
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    # Nextcloud runs behind reverse proxy, so no direct firewall access needed
    networking.firewall.allowedTCPPorts = [];
  });
}
