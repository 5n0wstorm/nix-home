{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.dev.gitea;
  homepageCfg = attrByPath ["fleet" "apps" "homepage"] {enable = false;} config;
  reverseProxyCfg = attrByPath ["fleet" "networking" "reverseProxy"] {enable = false;} config;

  # Safely check whether other modules are present (avoids evaluation failures on hosts
  # that don't import homepage/reverse-proxy).
  hasHomepageRegistry = hasAttrByPath ["fleet" "apps" "homepage" "serviceRegistry"] config;
  hasReverseProxyRegistry = hasAttrByPath ["fleet" "networking" "reverseProxy" "serviceRegistry"] config;

  defaultRootUrl =
    if (reverseProxyCfg.enable or false)
    then "https://${cfg.domain}/"
    else "http://${cfg.domain}:${toString cfg.port}/";
  effectiveRootUrl =
    if cfg.rootUrl != null
    then cfg.rootUrl
    else defaultRootUrl;
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

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address for Gitea to bind to (use 127.0.0.1 when behind reverse proxy)";
      example = "127.0.0.1";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall port for the Gitea HTTP interface";
    };

    domain = mkOption {
      type = types.str;
      default = "localhost";
      description = "Domain name for Gitea";
    };

    rootUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        External URL for Gitea (used for redirects/clone URLs). When unset, defaults to:
        - https://<domain>/ if reverse proxy is enabled
        - http://<domain>:<port>/ otherwise
      '';
      example = "https://git.example.com/";
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

    bypassAuth = mkOption {
      type = types.bool;
      default = true;
      description = "Bypass Authelia authentication (Gitea has built-in auth)";
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

    fleet.apps.homepage.serviceRegistry.gitea = mkIf (hasHomepageRegistry && cfg.homepage.enable && (homepageCfg.enable or false)) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = removeSuffix "/" effectiveRootUrl;
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.gitea = mkIf (hasReverseProxyRegistry && (reverseProxyCfg.enable or false)) {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.websockets" = "true";
        "fleet.authelia.bypass" =
          if cfg.bypassAuth
          then "true"
          else "false";
      };
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
          ROOT_URL = effectiveRootUrl;
          HTTP_PORT = cfg.port;
          HTTP_ADDR = cfg.listenAddress;
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
    # STATE DIRECTORY BOOTSTRAP
    # --------------------------------------------------------------------------
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 gitea gitea -"
      "d ${cfg.dataDir}/custom 0750 gitea gitea -"
      "d ${cfg.dataDir}/custom/conf 0750 gitea gitea -"
    ];

    systemd.services.gitea.preStart = mkBefore ''
      install -d -m 0750 -o gitea -g gitea ${escapeShellArg cfg.dataDir}/custom/conf
    '';

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
