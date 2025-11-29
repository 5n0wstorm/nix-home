{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.apps.vaultwarden;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager (Bitwarden compatible)";

    port = mkOption {
      type = types.port;
      default = 8222;
      description = "Port for Vaultwarden web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "bitwarden.local";
      description = "Domain name for Vaultwarden";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/vaultwarden";
      description = "Data directory for Vaultwarden";
    };

    backupDir = mkOption {
      type = types.nullOr types.str;
      default = "/var/backup/vaultwarden";
      description = "Backup directory for Vaultwarden data";
    };

    signupsAllowed = mkOption {
      type = types.bool;
      default = false;
      description = "Allow new user signups";
    };

    invitationsAllowed = mkOption {
      type = types.bool;
      default = true;
      description = "Allow admin to invite new users";
    };

    websocketEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable websocket notifications";
    };

    websocketPort = mkOption {
      type = types.port;
      default = 3012;
      description = "Port for websocket notifications";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Environment file containing secrets (ADMIN_TOKEN, SMTP_PASSWORD, etc.)";
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
        default = "Vaultwarden";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Password manager";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-bitwarden";
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

    fleet.apps.homepage.serviceRegistry.vaultwarden = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.vaultwarden = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.websockets" = "true";
        "fleet.reverse-proxy.extra-config" = ''
          client_max_body_size 525M;
        '';
        # Vaultwarden handles its own authentication
        "fleet.authelia.bypass" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # VAULTWARDEN SERVICE
    # --------------------------------------------------------------------------

    services.vaultwarden = {
      enable = true;
      backupDir = cfg.backupDir;
      environmentFile = cfg.environmentFile;

      config = {
        DOMAIN = "https://${cfg.domain}";
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = cfg.port;

        SIGNUPS_ALLOWED = cfg.signupsAllowed;
        INVITATIONS_ALLOWED = cfg.invitationsAllowed;

        WEBSOCKET_ENABLED = cfg.websocketEnabled;
        WEBSOCKET_PORT = cfg.websocketPort;

        # Security settings
        SHOW_PASSWORD_HINT = false;

        # Performance
        WEB_VAULT_ENABLED = true;
      };
    };

    # --------------------------------------------------------------------------
    # BACKUP DIRECTORY
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = mkIf (cfg.backupDir != null) [
      "d ${cfg.backupDir} 0700 vaultwarden vaultwarden -"
    ];

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port] ++ optional cfg.websocketEnabled cfg.websocketPort;
  };
}
