{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.media.jellyfin;
  sharedCfg = config.fleet.media.shared;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";

    port = mkOption {
      type = types.port;
      default = 8096;
      description = "Port for Jellyfin web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "jellyfin.local";
      description = "Domain name for Jellyfin";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/jellyfin";
      description = "Data directory for Jellyfin";
    };

    mediaDir = mkOption {
      type = types.str;
      default =
        if sharedCfg.enable
        then sharedCfg.paths.media.root
        else "/data/media";
      description = "Media directory for Jellyfin (defaults to shared media library root)";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Jellyfin";
    };

    bypassAuth = mkOption {
      type = types.bool;
      default = true;
      description = "Bypass Authelia authentication (Jellyfin has built-in auth)";
    };

    hardwareAcceleration = {
      enable = mkEnableOption "AMD VAAPI hardware-accelerated transcoding";

      type = mkOption {
        type = types.enum ["amd" "intel" "nvidia"];
        default = "amd";
        description = "Type of GPU for hardware acceleration";
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
        default = "Jellyfin";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Media streaming server";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-jellyfin";
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
    # JELLYFIN OVERLAY FOR SKIP INTRO BUTTON
    # --------------------------------------------------------------------------

    nixpkgs.overlays = [
      (_final: prev: {
        jellyfin-web = prev.jellyfin-web.overrideAttrs (
          _finalAttrs: _previousAttrs: {
            installPhase = ''
              runHook preInstall

              # Add skip intro button script to the HTML head
              sed -i "s#</head>#<script src=\"configurationpage?name=skip-intro-button.js\"></script></head>#" dist/index.html

              mkdir -p $out/share
              cp -a dist $out/share/jellyfin-web

              runHook postInstall
            '';
          }
        );
      })
    ];

    # --------------------------------------------------------------------------
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.jellyfin = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "jellyfin";
        url = "http://localhost:${toString cfg.port}";
        fields = ["movies" "series" "episodes"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.jellyfin = {
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
    # JELLYFIN SERVICE
    # --------------------------------------------------------------------------

    services.jellyfin = {
      enable = true;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.dataDir;
    };

    # --------------------------------------------------------------------------
    # HARDWARE ACCELERATION (AMD VAAPI)
    # --------------------------------------------------------------------------

    hardware.graphics = mkIf cfg.hardwareAcceleration.enable {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; (
        if cfg.hardwareAcceleration.type == "amd"
        then [
          # RADV (Mesa Vulkan) is enabled by default
          libva
          libvdpau-va-gl
          rocmPackages.clr
          rocmPackages.clr.icd
          vulkan-loader
          # Required for Jellyfin's Vulkan-based subtitle overlay
          libplacebo
          shaderc
        ]
        else if cfg.hardwareAcceleration.type == "intel"
        then [
          intel-media-driver
          intel-vaapi-driver
          libva
          libvdpau-va-gl
          vpl-gpu-rt
        ]
        else []
      );
    };

    # Add jellyfin user to video and render groups for GPU access
    users.groups.video.members = mkIf cfg.hardwareAcceleration.enable ["jellyfin"];
    users.groups.render.members = mkIf cfg.hardwareAcceleration.enable ["jellyfin"];

    # Debugging tools for hardware acceleration
    environment.systemPackages = mkIf cfg.hardwareAcceleration.enable (with pkgs; [
      libva-utils # vainfo for debugging VAAPI
      vulkan-tools # vulkaninfo for debugging Vulkan
    ]);

    # --------------------------------------------------------------------------
    # FONT CONFIGURATION FOR SUBTITLE RENDERING
    # --------------------------------------------------------------------------
    # FFmpeg/libass requires fonts and fontconfig for ASS/SSA subtitle rendering.
    # Without proper configuration, subtitle burn-in will fail with exit code 254.

    fonts.fontconfig.enable = true;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
      dejavu_fonts
    ];

    # Ensure Jellyfin's ffmpeg can find fonts via fontconfig and Vulkan drivers
    # HOME is needed for fontconfig cache, FONTCONFIG_PATH for font discovery
    systemd.services.jellyfin.environment =
      {
        FONTCONFIG_PATH = "/etc/fonts";
        FONTCONFIG_FILE = "/etc/fonts/fonts.conf";
        HOME = cfg.dataDir;
      }
      // (optionalAttrs cfg.hardwareAcceleration.enable {
        # Vulkan ICD discovery for hardware subtitle overlay
        VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
        LIBVA_DRIVER_NAME = "radeonsi";
      });

    # Create fontconfig cache directory for jellyfin user
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}/.cache 0755 jellyfin jellyfin -"
      "d ${cfg.dataDir}/.cache/fontconfig 0755 jellyfin jellyfin -"
    ];

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
