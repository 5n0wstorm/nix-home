{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.fredy;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.fredy = {
    enable = mkEnableOption "Fredy real estate finder (German property portals)";

    port = mkOption {
      type = types.port;
      default = 9998;
      description = "Port for the Fredy web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "immo.local";
      description = "Domain name for Fredy";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/orangecoding/fredy:22.9.1";
      description = "OCI image for Fredy";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/fredy";
      description = "Base data directory (conf/ and db/ subdirectories)";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Expose the service port on all interfaces (off when behind the fleet reverse proxy)";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind the container port to";
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
        default = "Fredy";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "German real estate search automation";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "mdi-home-search";
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

  config = mkIf cfg.enable let
    confDir = "${cfg.dataDir}/conf";
    dbDir = "${cfg.dataDir}/db";
    hostPort =
      if cfg.openFirewall
      then toString cfg.port
      else "${cfg.listenAddress}:${toString cfg.port}";
  in {
    # --------------------------------------------------------------------------
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.fredy = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.fredy = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.websockets" = "true";
        "fleet.authelia.bypass" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # PODMAN / OCI CONTAINERS
    # --------------------------------------------------------------------------

    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };
    virtualisation.oci-containers.backend = "podman";

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${confDir} 0755 root root -"
      "d ${dbDir} 0755 root root -"
    ];

    systemd.services.fredy-config = {
      description = "Bootstrap Fredy config.json if missing";
      before = ["podman-fredy.service"];
      requiredBy = ["podman-fredy.service"];
      wantedBy = ["multi-user.target"];

      path = [pkgs.coreutils];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        if [ ! -f ${confDir}/config.json ]; then
          printf '%s\n' '{"sqlitepath":"/db"}' > ${confDir}/config.json
          chmod 0644 ${confDir}/config.json
        fi
      '';
    };

    virtualisation.oci-containers.containers.fredy = {
      image = cfg.image;

      ports = [
        "${hostPort}:9998"
      ];

      volumes = [
        "${confDir}:/conf"
        "${dbDir}:/db"
      ];
    };

    systemd.services."podman-fredy" = {
      requires = ["podman.service" "fredy-config.service"];
      after = ["podman.service" "fredy-config.service"];
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
