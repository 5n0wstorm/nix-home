{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.dev.gitea;
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
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
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
