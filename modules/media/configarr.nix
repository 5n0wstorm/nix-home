{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.media.configarr;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.configarr = {
    enable = mkEnableOption "Configarr - TRaSH Guides configuration sync for Sonarr/Radarr";

    configDir = mkOption {
      type = types.str;
      default = "/var/lib/configarr";
      description = "Configuration directory for Configarr";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to the Configarr config.yml file.
        If null, a default configuration will be generated.
      '';
    };

    secretsFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to the secrets.yml file containing API keys.
        Should contain SONARR_API_KEY and RADARR_API_KEY.
      '';
      example = "/run/secrets/configarr/secrets.yml";
    };

    schedule = mkOption {
      type = types.str;
      default = "daily";
      description = ''
        Systemd calendar expression for when to run Configarr.
        Examples: "daily", "hourly", "*-*-* 03:00:00"
      '';
    };

    # Sonarr configuration
    sonarr = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Sync configuration to Sonarr";
      };

      url = mkOption {
        type = types.str;
        default = "http://localhost:8989";
        description = "Sonarr URL";
      };

      apiKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing Sonarr API key";
        example = "/run/secrets/sonarr/api-key";
      };
    };

    # Radarr configuration
    radarr = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Sync configuration to Radarr";
      };

      url = mkOption {
        type = types.str;
        default = "http://localhost:7878";
        description = "Radarr URL";
      };

      apiKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing Radarr API key";
        example = "/run/secrets/radarr/api-key";
      };
    };

    # TRaSH Guides sync options
    trashGuides = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Sync custom formats from TRaSH Guides";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # ASSERTIONS
    # --------------------------------------------------------------------------

    assertions = [
      {
        assertion = cfg.sonarr.enable -> cfg.sonarr.apiKeyFile != null;
        message = "Sonarr API key file must be specified when Sonarr sync is enabled";
      }
      {
        assertion = cfg.radarr.enable -> cfg.radarr.apiKeyFile != null;
        message = "Radarr API key file must be specified when Radarr sync is enabled";
      }
    ];

    # --------------------------------------------------------------------------
    # DIRECTORY SETUP
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 0750 root root -"
    ];

    # --------------------------------------------------------------------------
    # CONFIGARR SECRETS PREPARATION SERVICE
    # Creates secrets.yml from individual API key files
    # --------------------------------------------------------------------------

    systemd.services.configarr-secrets = {
      description = "Prepare Configarr secrets file";
      before = ["configarr.service"];
      requiredBy = ["configarr.service"];

      path = [pkgs.coreutils];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        mkdir -p ${cfg.configDir}

        # Build secrets.yml from API key files
        echo "# Auto-generated secrets file" > ${cfg.configDir}/secrets.yml

        ${optionalString cfg.sonarr.enable ''
          SONARR_KEY=$(cat ${cfg.sonarr.apiKeyFile} | tr -d '[:space:]')
          echo "SONARR_API_KEY: $SONARR_KEY" >> ${cfg.configDir}/secrets.yml
        ''}

        ${optionalString cfg.radarr.enable ''
          RADARR_KEY=$(cat ${cfg.radarr.apiKeyFile} | tr -d '[:space:]')
          echo "RADARR_API_KEY: $RADARR_KEY" >> ${cfg.configDir}/secrets.yml
        ''}

        chmod 600 ${cfg.configDir}/secrets.yml
        echo "Configarr secrets prepared"
      '';
    };

    # --------------------------------------------------------------------------
    # CONFIGARR CONFIG GENERATION SERVICE
    # Creates config.yml with TRaSH Guides integration
    # --------------------------------------------------------------------------

    systemd.services.configarr-config = mkIf (cfg.configFile == null) {
      description = "Generate Configarr configuration";
      before = ["configarr.service"];
      requiredBy = ["configarr.service"];
      after = ["configarr-secrets.service"];

      path = [pkgs.coreutils];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        mkdir -p ${cfg.configDir}

        cat > ${cfg.configDir}/config.yml << 'EOF'
        # Configarr configuration - Auto-generated
        # Syncs TRaSH Guides custom formats and quality profiles

        trashGuideUrl: https://github.com/TRaSH-Guides/Guides
        recyclarrConfigUrl: https://github.com/recyclarr/config-templates

        ${optionalString cfg.sonarr.enable ''
          sonarr:
            series:
              base_url: ${cfg.sonarr.url}
              api_key: !secret SONARR_API_KEY

              quality_definition:
                type: series

              custom_formats:
                - trash_ids:
                    # Unwanted
                    - 85c61753df5da1fb2aab6f2a47426b09  # BR-DISK
                    - 9c11cd3f07101cdba90a2d81cf0e56b4  # LQ
                    - e2315f990da2e2cbfc9fa5b7a6fcfe48  # LQ (Release Title)
                    - 47435ece6b99a0b477caf360e79ba0bb  # x265 (HD)
                    # HQ Source Groups
                    - e6258996055b9fbab7e9cb2f75819294  # WEB Tier 01
                    - 58790d4e2fdcd9733aa7ae68ba2bb503  # WEB Tier 02
                    - d84935abd3f8556dcd51d4f27e22f0a6  # WEB Tier 03
                    # Streaming Services
                    - d660701077794679fd59e8bdf4ce3a29  # AMZN
                    - f67c9ca88f463a48346062e8ad07713f  # ATVP
                    - 36b72f59f4ea20aad9316f475f2d9fbb  # DCU
                    - 89358767a60cc28783cdc3d0be9388a4  # DSNP
                    - 7a235133c87f7da4c8571f00e6c2c636  # HBO
                    - a880d6abc21e7c16f2c1ff87b4898f04  # HMAX
                    - f6cce30f1733d5c8194222a7507f5f49  # HULU
                    - 0ac24a2a68a9700bcb7eeca8e5cd644c  # iT
                    - 81d1fbf600e2540cee87f3a23f9d3c1c  # MAX
                    - d34870697c9db575f17700212167be23  # NF
                    - 1656adc6d7bb2c8cca6acfb6592db421  # PCOK
                    - c67a75ae4a1715f2bb4d492f17f45d32  # PMTP
                    - 3ac5d84fce98bab1b531393e9c82f467  # QIBI
                    - c30d2c5b3f5f3d6e7a5e5b7f7e7f7e7f  # STAN
                  quality_profiles:
                    - name: WEB-DL (1080p)
        ''}

        ${optionalString cfg.radarr.enable ''
          radarr:
            movies:
              base_url: ${cfg.radarr.url}
              api_key: !secret RADARR_API_KEY

              quality_definition:
                type: movie

              custom_formats:
                - trash_ids:
                    # Unwanted
                    - ed38b889b31be83fda192888e2286d83  # BR-DISK
                    - 90a6f9a284dff5103f6346090e6280c8  # LQ
                    - e204b80c87be9497a8a6eaff48f72905  # LQ (Release Title)
                    - dc98083864ea246d05a42df0d05f81cc  # x265 (HD)
                    # HQ Release Groups
                    - ed27ebfef2f323e964fb1f61f8322f43  # BluRay Tier 01
                    - c20c8647f2746a1f4c4262b0fbbeeeae  # BluRay Tier 02
                    - 5608c71bcebba0a5e666223bae8c9227  # BluRay Tier 03
                    - c20f169ef63c5f40c2def54abaf4438e  # WEB Tier 01
                    - 403816d65392c79236dcb6dd591aedd4  # WEB Tier 02
                    - af94e0fe497124d1f9ce732069ec8c3b  # WEB Tier 03
                    # Streaming Services
                    - b3b3a6ac74ecbd56bcdbefa4799fb9df  # AMZN
                    - 40e9380490e748672c2522eaaeb692f7  # ATVP
                    - cc5e51a9e85a6296ceefe097a77f12f4  # BCORE
                    - 16622a6911d1ab5d5b8b713f5f813873  # CRiT
                    - 84272245b2988854bfb76a16e60baea5  # DSNP
                    - 509e5f41146e278f9eab1ddaceb34515  # HBO
                    - 5763d1b0ce84aff3b21038c50f8f0f5a  # HMAX
                    - 526d445d4c16214309f0fd2b3be18a89  # Hulu
                    - 2a6039655313bf5dab1e43523b62c374  # MA
                    - 6a061313d22e51e0f25b7cd4dc065233  # MAX
                    - 170b1d363bd8516fbf3a3eb05d4faff6  # NF
                    - fbca986396c5e695ef7b2def3c755d01  # OViD
                    - bf7e73dd1d85b12cc527dc619761c840  # Pathe
                    - c9fd353f8f5f1baf56dc601c4cb29920  # PCOK
                    - e36a0ba1bc902b26ee40818a1d59b8bd  # PMTP
                    - c2863d2a50c9acad1fb50e53ece60817  # STAN
                  quality_profiles:
                    - name: HD Bluray + WEB
        ''}
        EOF

        echo "Configarr config generated"
      '';
    };

    # --------------------------------------------------------------------------
    # CONFIGARR ONE-SHOT SERVICE
    # Runs Configarr to sync configurations
    # --------------------------------------------------------------------------

    systemd.services.configarr = {
      description = "Configarr - Sync TRaSH Guides to Sonarr/Radarr";
      after =
        ["network-online.target" "configarr-secrets.service"]
        ++ optional cfg.sonarr.enable "sonarr.service"
        ++ optional cfg.radarr.enable "radarr.service";
      wants = ["network-online.target"];

      path = [pkgs.podman];

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "10min";
      };

      script = let
        configPath =
          if cfg.configFile != null
          then cfg.configFile
          else "${cfg.configDir}/config.yml";
      in ''
        echo "Running Configarr sync..."

        ${pkgs.podman}/bin/podman run --rm \
          --name configarr \
          -v ${configPath}:/app/config.yml:ro \
          -v ${cfg.configDir}/secrets.yml:/app/secrets.yml:ro \
          --network host \
          ghcr.io/configarr/configarr:latest

        echo "Configarr sync completed"
      '';
    };

    # --------------------------------------------------------------------------
    # CONFIGARR TIMER
    # Runs Configarr on schedule
    # --------------------------------------------------------------------------

    systemd.timers.configarr = {
      description = "Run Configarr periodically";
      wantedBy = ["timers.target"];

      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
}
