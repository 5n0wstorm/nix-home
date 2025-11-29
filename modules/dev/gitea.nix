{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.dev.gitea;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.dev.gitea = {
    enable = mkEnableOption "Gitea Git repository hosting";

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Gitea web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "localhost";
      description = "Domain name for Gitea";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/gitea";
      description = "Data directory for Gitea";
    };

    appName = mkOption {
      type = types.str;
      default = "Fleet Git";
      description = "Application name for Gitea";
    };

    disableRegistration = mkOption {
      type = types.bool;
      default = false;
      description = "Disable user registration";
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
        default = "Gitea";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Git repository hosting";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-gitea";
        description = "Icon for homepage (mdi-*, si-*, or URL)";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Dev";
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

    fleet.apps.homepage.serviceRegistry.gitea = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "http://${cfg.domain}:${toString cfg.port}";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # GITEA SERVICE
    # --------------------------------------------------------------------------

    services.gitea = {
      enable = true;
      appName = cfg.appName;
      stateDir = cfg.dataDir;

      settings = {
        server = {
          DOMAIN = cfg.domain;
          ROOT_URL = "http://${cfg.domain}:${toString cfg.port}/";
          HTTP_PORT = cfg.port;
          DISABLE_SSH = false;
          SSH_PORT = 22;
        };

        service = {
          DISABLE_REGISTRATION = cfg.disableRegistration;
          REQUIRE_SIGNIN_VIEW = false;
        };

        mailer = {
          ENABLED = false;
          SENDMAIL_PATH = "${pkgs.system-sendmail}/bin/sendmail";
        };

        repository = {
          DEFAULT_BRANCH = "main";
        };

        # Backup configuration
        dump = {
          ENABLED = true;
          SCHEDULE = "@midnight";
          RETENTION_DAYS = 7;
        };
      };

      database = {
        type = "sqlite3";
        path = "${cfg.dataDir}/data/gitea.db";
      };

      lfs.enable = true;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
