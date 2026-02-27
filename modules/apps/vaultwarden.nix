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

    # SMTP (mail) configuration; credentials from sops secrets
    smtp = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SMTP for verification emails and invitations";
      };

      from = mkOption {
        type = types.str;
        default = "";
        description = "Sender email address (e.g. vaultwarden@example.com)";
      };

      hostFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing SMTP host (e.g. from sops secret bitwarden/smtp-address)";
      };

      passwordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing SMTP password (e.g. from sops secret bitwarden/smtp-password)";
      };

      port = mkOption {
        type = types.port;
        default = 587;
        description = "SMTP port (used when host file does not contain ':port')";
      };

      security = mkOption {
        type = types.enum ["starttls" "force_tls" "off"];
        default = "starttls";
        description = "SMTP encryption: starttls (587), force_tls (465), or off (25)";
      };

      username = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SMTP username (optional; omit if same as from or no auth)";
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

    # Build SMTP env file from sops secrets (host + password files)
    systemd.services.vaultwarden-smtp-secrets = mkIf (cfg.smtp.enable && cfg.smtp.hostFile != null && cfg.smtp.passwordFile != null) {
      description = "Prepare Vaultwarden SMTP environment file from secrets";
      before = ["vaultwarden.service"];
      requiredBy = ["vaultwarden.service"];
      after = ["sops-nix.service"];
      wants = ["sops-nix.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/vaultwarden
        chmod 755 /run/vaultwarden

        SMTP_ADDR=$(cat "${cfg.smtp.hostFile}" | tr -d '\n')
        if echo "$SMTP_ADDR" | grep -q ':'; then
          SMTP_HOST="''${SMTP_ADDR%%:*}"
          SMTP_PORT="''${SMTP_ADDR#*:}"
        else
          SMTP_HOST="$SMTP_ADDR"
          SMTP_PORT="${toString cfg.smtp.port}"
        fi

        SMTP_PASSWORD=$(cat "${cfg.smtp.passwordFile}" | tr -d '\n')

        # Vaultwarden requires both SMTP_USERNAME and SMTP_PASSWORD when using auth
        SMTP_USER="${if cfg.smtp.username != null then cfg.smtp.username else cfg.smtp.from}"

        # No leading spaces: systemd EnvironmentFile keys must not have whitespace
        {
          echo "SMTP_HOST=$SMTP_HOST"
          echo "SMTP_PORT=$SMTP_PORT"
          echo "SMTP_FROM=${cfg.smtp.from}"
          echo "SMTP_SECURITY=${cfg.smtp.security}"
          echo "SMTP_USERNAME=$SMTP_USER"
          printf 'SMTP_PASSWORD=%s\n' "$SMTP_PASSWORD"
        } > /run/vaultwarden/smtp.env
        chmod 600 /run/vaultwarden/smtp.env
      '';
    };

    services.vaultwarden = {
      enable = true;
      backupDir = cfg.backupDir;
      environmentFile = let
        base = optional (cfg.environmentFile != null) cfg.environmentFile;
        smtpEnv = optional (cfg.smtp.enable && cfg.smtp.hostFile != null && cfg.smtp.passwordFile != null) "/run/vaultwarden/smtp.env";
      in base ++ smtpEnv;

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
