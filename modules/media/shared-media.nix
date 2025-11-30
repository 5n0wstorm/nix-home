{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.media.shared;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.shared = {
    enable = mkEnableOption "Shared media directory structure for all *arr apps";

    baseDir = mkOption {
      type = types.str;
      default = "/media";
      description = "Base directory for all media";
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = "Shared group for media access";
    };

    gid = mkOption {
      type = types.int;
      default = 1500;
      description = "GID for the media group";
    };

    directories = {
      downloads = mkOption {
        type = types.str;
        default = "downloads";
        description = "Subdirectory for downloads (relative to baseDir)";
      };

      tv = mkOption {
        type = types.str;
        default = "tv";
        description = "Subdirectory for TV shows (relative to baseDir)";
      };

      movies = mkOption {
        type = types.str;
        default = "movies";
        description = "Subdirectory for movies (relative to baseDir)";
      };

      music = mkOption {
        type = types.str;
        default = "music";
        description = "Subdirectory for music (relative to baseDir)";
      };

      books = mkOption {
        type = types.str;
        default = "books";
        description = "Subdirectory for books/ebooks (relative to baseDir)";
      };

      audiobooks = mkOption {
        type = types.str;
        default = "audiobooks";
        description = "Subdirectory for audiobooks (relative to baseDir)";
      };
    };

    # Computed full paths (read-only)
    paths = {
      downloads = mkOption {
        type = types.str;
        default = "${cfg.baseDir}/${cfg.directories.downloads}";
        readOnly = true;
        description = "Full path to downloads directory";
      };

      tv = mkOption {
        type = types.str;
        default = "${cfg.baseDir}/${cfg.directories.tv}";
        readOnly = true;
        description = "Full path to TV directory";
      };

      movies = mkOption {
        type = types.str;
        default = "${cfg.baseDir}/${cfg.directories.movies}";
        readOnly = true;
        description = "Full path to movies directory";
      };

      music = mkOption {
        type = types.str;
        default = "${cfg.baseDir}/${cfg.directories.music}";
        readOnly = true;
        description = "Full path to music directory";
      };

      books = mkOption {
        type = types.str;
        default = "${cfg.baseDir}/${cfg.directories.books}";
        readOnly = true;
        description = "Full path to books directory";
      };

      audiobooks = mkOption {
        type = types.str;
        default = "${cfg.baseDir}/${cfg.directories.audiobooks}";
        readOnly = true;
        description = "Full path to audiobooks directory";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # MEDIA GROUP
    # --------------------------------------------------------------------------

    users.groups.${cfg.group} = {
      gid = cfg.gid;
    };

    # --------------------------------------------------------------------------
    # SERVICE GROUP CONFIGURATION
    # Set the media group for services that support it directly
    # --------------------------------------------------------------------------

    # Use mkForce to ensure media group is used for all services
    # This allows hardlinks between downloads and library directories
    services.sonarr.group = mkIf (config.services.sonarr.enable or false) (mkForce cfg.group);
    services.radarr.group = mkIf (config.services.radarr.enable or false) (mkForce cfg.group);
    services.lidarr.group = mkIf (config.services.lidarr.enable or false) (mkForce cfg.group);
    services.readarr.group = mkIf (config.services.readarr.enable or false) (mkForce cfg.group);
    services.bazarr.group = mkIf (config.services.bazarr.enable or false) (mkForce cfg.group);
    services.jellyfin.group = mkIf (config.services.jellyfin.enable or false) (mkForce cfg.group);
    services.sabnzbd.group = mkIf (config.services.sabnzbd.enable or false) (mkForce cfg.group);

    # --------------------------------------------------------------------------
    # SYSTEMD SUPPLEMENTARY GROUPS
    # For services that use DynamicUser or don't have a group option
    # --------------------------------------------------------------------------

    systemd.services.prowlarr.serviceConfig.SupplementaryGroups = 
      mkIf (config.services.prowlarr.enable or false) [cfg.group];
    
    systemd.services.transmission.serviceConfig.SupplementaryGroups = 
      mkIf (config.services.transmission.enable or false) [cfg.group];

    # --------------------------------------------------------------------------
    # DIRECTORY STRUCTURE
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      # Base media directory
      "d ${cfg.baseDir} 0775 root ${cfg.group} -"

      # Downloads directory with subdirectories for different types
      "d ${cfg.paths.downloads} 0775 root ${cfg.group} -"
      "d ${cfg.paths.downloads}/complete 0775 root ${cfg.group} -"
      "d ${cfg.paths.downloads}/incomplete 0775 root ${cfg.group} -"
      "d ${cfg.paths.downloads}/torrents 0775 root ${cfg.group} -"
      "d ${cfg.paths.downloads}/usenet 0775 root ${cfg.group} -"

      # Media library directories
      "d ${cfg.paths.tv} 0775 root ${cfg.group} -"
      "d ${cfg.paths.movies} 0775 root ${cfg.group} -"
      "d ${cfg.paths.music} 0775 root ${cfg.group} -"
      "d ${cfg.paths.books} 0775 root ${cfg.group} -"
      "d ${cfg.paths.audiobooks} 0775 root ${cfg.group} -"
    ];

    # --------------------------------------------------------------------------
    # SET GROUP STICKY BIT
    # Ensures new files inherit the media group
    # --------------------------------------------------------------------------

    systemd.services.media-permissions = {
      description = "Set media directory permissions";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Set group sticky bit so new files inherit the media group
        chmod g+s ${cfg.baseDir}
        chmod g+s ${cfg.paths.downloads}
        chmod g+s ${cfg.paths.downloads}/complete
        chmod g+s ${cfg.paths.downloads}/incomplete
        chmod g+s ${cfg.paths.downloads}/torrents
        chmod g+s ${cfg.paths.downloads}/usenet
        chmod g+s ${cfg.paths.tv}
        chmod g+s ${cfg.paths.movies}
        chmod g+s ${cfg.paths.music}
        chmod g+s ${cfg.paths.books}
        chmod g+s ${cfg.paths.audiobooks}

        # Ensure group write permissions
        chmod 2775 ${cfg.baseDir}
        chmod 2775 ${cfg.paths.downloads}
        chmod 2775 ${cfg.paths.downloads}/complete
        chmod 2775 ${cfg.paths.downloads}/incomplete
        chmod 2775 ${cfg.paths.downloads}/torrents
        chmod 2775 ${cfg.paths.downloads}/usenet
        chmod 2775 ${cfg.paths.tv}
        chmod 2775 ${cfg.paths.movies}
        chmod 2775 ${cfg.paths.music}
        chmod 2775 ${cfg.paths.books}
        chmod 2775 ${cfg.paths.audiobooks}
      '';
    };
  };
}

