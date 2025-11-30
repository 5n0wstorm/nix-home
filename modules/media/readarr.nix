{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.media.readarr;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.readarr = {
    enable = mkEnableOption "Readarr ebook management";

    port = mkOption {
      type = types.port;
      default = 8787;
      description = "Port for Readarr web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "readarr.local";
      description = "Domain name for Readarr";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/readarr";
      description = "Data directory for Readarr";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Readarr";
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
        default = "Readarr";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Ebook manager";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-readarr";
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

    fleet.apps.homepage.serviceRegistry.readarr = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "readarr";
        url = "http://localhost:${toString cfg.port}";
        fields = ["wanted" "queued" "books"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.readarr = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # READARR SERVICE
    # --------------------------------------------------------------------------

    services.readarr = {
      enable = true;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.dataDir;
    };

    # --------------------------------------------------------------------------
    # DISABLE BUILT-IN AUTH (handled by Authelia)
    # --------------------------------------------------------------------------

    systemd.services.readarr.preStart = let
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
