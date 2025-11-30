{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.media.sonarr;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.sonarr = {
    enable = mkEnableOption "Sonarr TV series management";

    port = mkOption {
      type = types.port;
      default = 8989;
      description = "Port for Sonarr web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "sonarr.local";
      description = "Domain name for Sonarr";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/sonarr";
      description = "Data directory for Sonarr";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Sonarr";
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
        default = "Sonarr";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "TV series manager";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-sonarr";
        description = "Icon for homepage";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Media";
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

    fleet.apps.homepage.serviceRegistry.sonarr = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "sonarr";
        url = "http://localhost:${toString cfg.port}";
        fields = ["wanted" "queued" "series"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.sonarr = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # SONARR SERVICE
    # --------------------------------------------------------------------------

    services.sonarr = {
      enable = true;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.dataDir;
    };

    # --------------------------------------------------------------------------
    # DISABLE BUILT-IN AUTH (handled by Authelia)
    # --------------------------------------------------------------------------

    systemd.services.sonarr.preStart = let
      configFile = "${cfg.dataDir}/config.xml";
    in ''
      if [ -f "${configFile}" ]; then
        # Set authentication to External (handled by reverse proxy/Authelia)
        ${pkgs.gnused}/bin/sed -i 's|<AuthenticationMethod>[^<]*</AuthenticationMethod>|<AuthenticationMethod>External</AuthenticationMethod>|g' "${configFile}"
        ${pkgs.gnused}/bin/sed -i 's|<AuthenticationRequired>[^<]*</AuthenticationRequired>|<AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>|g' "${configFile}"
      fi
    '';

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
