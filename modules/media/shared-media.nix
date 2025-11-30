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
      default = "/data";
      description = "Base directory for all media (recommended: /data)";
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

    # --------------------------------------------------------------------------
    # DIRECTORY SUBDIRECTORY NAMES
    # --------------------------------------------------------------------------

    directories = {
      # Torrent download directories (per category)
      torrents = {
        root = mkOption {
          type = types.str;
          default = "torrents";
          description = "Subdirectory for torrent downloads (relative to baseDir)";
        };

        books = mkOption {
          type = types.str;
          default = "books";
          description = "Subdirectory for book torrents";
        };

        movies = mkOption {
          type = types.str;
          default = "movies";
          description = "Subdirectory for movie torrents";
        };

        music = mkOption {
          type = types.str;
          default = "music";
          description = "Subdirectory for music torrents";
        };

        tv = mkOption {
          type = types.str;
          default = "tv";
          description = "Subdirectory for TV torrents";
        };
      };

      # Usenet download directories
      usenet = {
        root = mkOption {
          type = types.str;
          default = "usenet";
          description = "Subdirectory for usenet downloads (relative to baseDir)";
        };

        incomplete = mkOption {
          type = types.str;
          default = "incomplete";
          description = "Subdirectory for incomplete usenet downloads";
        };

        complete = mkOption {
          type = types.str;
          default = "complete";
          description = "Subdirectory for complete usenet downloads";
        };

        books = mkOption {
          type = types.str;
          default = "books";
          description = "Subdirectory for completed book downloads";
        };

        movies = mkOption {
          type = types.str;
          default = "movies";
          description = "Subdirectory for completed movie downloads";
        };

        music = mkOption {
          type = types.str;
          default = "music";
          description = "Subdirectory for completed music downloads";
        };

        tv = mkOption {
          type = types.str;
          default = "tv";
          description = "Subdirectory for completed TV downloads";
        };
      };

      # Final media library directories
      media = {
        root = mkOption {
          type = types.str;
          default = "media";
          description = "Subdirectory for final media library (relative to baseDir)";
        };

        books = mkOption {
          type = types.str;
          default = "books";
          description = "Subdirectory for books library";
        };

        movies = mkOption {
          type = types.str;
          default = "movies";
          description = "Subdirectory for movies library";
        };

        music = mkOption {
          type = types.str;
          default = "music";
          description = "Subdirectory for music library";
        };

        tv = mkOption {
          type = types.str;
          default = "tv";
          description = "Subdirectory for TV library";
        };
      };
    };

    # --------------------------------------------------------------------------
    # COMPUTED FULL PATHS (read-only)
    # --------------------------------------------------------------------------

    paths = {
      # Torrent paths
      torrents = {
        root = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.torrents.root}";
          readOnly = true;
          description = "Full path to torrents directory";
        };

        books = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.torrents.root}/${cfg.directories.torrents.books}";
          readOnly = true;
          description = "Full path to book torrents directory";
        };

        movies = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.torrents.root}/${cfg.directories.torrents.movies}";
          readOnly = true;
          description = "Full path to movie torrents directory";
        };

        music = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.torrents.root}/${cfg.directories.torrents.music}";
          readOnly = true;
          description = "Full path to music torrents directory";
        };

        tv = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.torrents.root}/${cfg.directories.torrents.tv}";
          readOnly = true;
          description = "Full path to TV torrents directory";
        };
      };

      # Usenet paths
      usenet = {
        root = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.usenet.root}";
          readOnly = true;
          description = "Full path to usenet directory";
        };

        incomplete = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.usenet.root}/${cfg.directories.usenet.incomplete}";
          readOnly = true;
          description = "Full path to incomplete usenet directory";
        };

        complete = {
          root = mkOption {
            type = types.str;
            default = "${cfg.baseDir}/${cfg.directories.usenet.root}/${cfg.directories.usenet.complete}";
            readOnly = true;
            description = "Full path to complete usenet directory";
          };

          books = mkOption {
            type = types.str;
            default = "${cfg.baseDir}/${cfg.directories.usenet.root}/${cfg.directories.usenet.complete}/${cfg.directories.usenet.books}";
            readOnly = true;
            description = "Full path to completed book downloads";
          };

          movies = mkOption {
            type = types.str;
            default = "${cfg.baseDir}/${cfg.directories.usenet.root}/${cfg.directories.usenet.complete}/${cfg.directories.usenet.movies}";
            readOnly = true;
            description = "Full path to completed movie downloads";
          };

          music = mkOption {
            type = types.str;
            default = "${cfg.baseDir}/${cfg.directories.usenet.root}/${cfg.directories.usenet.complete}/${cfg.directories.usenet.music}";
            readOnly = true;
            description = "Full path to completed music downloads";
          };

          tv = mkOption {
            type = types.str;
            default = "${cfg.baseDir}/${cfg.directories.usenet.root}/${cfg.directories.usenet.complete}/${cfg.directories.usenet.tv}";
            readOnly = true;
            description = "Full path to completed TV downloads";
          };
        };
      };

      # Media library paths
      media = {
        root = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.media.root}";
          readOnly = true;
          description = "Full path to media library directory";
        };

        books = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.media.root}/${cfg.directories.media.books}";
          readOnly = true;
          description = "Full path to books library";
        };

        movies = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.media.root}/${cfg.directories.media.movies}";
          readOnly = true;
          description = "Full path to movies library";
        };

        music = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.media.root}/${cfg.directories.media.music}";
          readOnly = true;
          description = "Full path to music library";
        };

        tv = mkOption {
          type = types.str;
          default = "${cfg.baseDir}/${cfg.directories.media.root}/${cfg.directories.media.tv}";
          readOnly = true;
          description = "Full path to TV library";
        };
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

    users.users.dominik.extraGroups = [cfg.group];

    # --------------------------------------------------------------------------
    # SYSTEMD SUPPLEMENTARY GROUPS
    # Add media group as supplementary so services can access media directories
    # but keep their own data directories (/var/lib/*) with original ownership
    # --------------------------------------------------------------------------

    systemd.services.sonarr.serviceConfig.SupplementaryGroups =
      mkIf (config.services.sonarr.enable or false) [cfg.group];

    systemd.services.radarr.serviceConfig.SupplementaryGroups =
      mkIf (config.services.radarr.enable or false) [cfg.group];

    systemd.services.lidarr.serviceConfig.SupplementaryGroups =
      mkIf (config.services.lidarr.enable or false) [cfg.group];

    systemd.services.readarr.serviceConfig.SupplementaryGroups =
      mkIf (config.services.readarr.enable or false) [cfg.group];

    systemd.services.bazarr.serviceConfig.SupplementaryGroups =
      mkIf (config.services.bazarr.enable or false) [cfg.group];

    systemd.services.jellyfin.serviceConfig.SupplementaryGroups =
      mkIf (config.services.jellyfin.enable or false) [cfg.group];

    systemd.services.sabnzbd.serviceConfig.SupplementaryGroups =
      mkIf (config.services.sabnzbd.enable or false) [cfg.group];

    systemd.services.prowlarr.serviceConfig.SupplementaryGroups =
      mkIf (config.services.prowlarr.enable or false) [cfg.group];

    systemd.services.transmission.serviceConfig.SupplementaryGroups =
      mkIf (config.services.transmission.enable or false) [cfg.group];

    # --------------------------------------------------------------------------
    # DIRECTORY STRUCTURE
    # Creates the TRaSH-guide recommended folder structure:
    #
    # baseDir/
    # ├── torrents/
    # │   ├── books/
    # │   ├── movies/
    # │   ├── music/
    # │   └── tv/
    # ├── usenet/
    # │   ├── incomplete/
    # │   └── complete/
    # │       ├── books/
    # │       ├── movies/
    # │       ├── music/
    # │       └── tv/
    # └── media/
    #     ├── books/
    #     ├── movies/
    #     ├── music/
    #     └── tv/
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      # Base directory
      "d ${cfg.baseDir} 0775 root ${cfg.group} -"

      # Torrent directories (per category)
      "d ${cfg.paths.torrents.root} 0775 root ${cfg.group} -"
      "d ${cfg.paths.torrents.books} 0775 root ${cfg.group} -"
      "d ${cfg.paths.torrents.movies} 0775 root ${cfg.group} -"
      "d ${cfg.paths.torrents.music} 0775 root ${cfg.group} -"
      "d ${cfg.paths.torrents.tv} 0775 root ${cfg.group} -"

      # Usenet directories
      "d ${cfg.paths.usenet.root} 0775 root ${cfg.group} -"
      "d ${cfg.paths.usenet.incomplete} 0775 root ${cfg.group} -"
      "d ${cfg.paths.usenet.complete.root} 0775 root ${cfg.group} -"
      "d ${cfg.paths.usenet.complete.books} 0775 root ${cfg.group} -"
      "d ${cfg.paths.usenet.complete.movies} 0775 root ${cfg.group} -"
      "d ${cfg.paths.usenet.complete.music} 0775 root ${cfg.group} -"
      "d ${cfg.paths.usenet.complete.tv} 0775 root ${cfg.group} -"

      # Media library directories
      "d ${cfg.paths.media.root} 0775 root ${cfg.group} -"
      "d ${cfg.paths.media.books} 0775 root ${cfg.group} -"
      "d ${cfg.paths.media.movies} 0775 root ${cfg.group} -"
      "d ${cfg.paths.media.music} 0775 root ${cfg.group} -"
      "d ${cfg.paths.media.tv} 0775 root ${cfg.group} -"
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
        # Base directory
        chmod g+s ${cfg.baseDir}

        # Torrent directories
        chmod g+s ${cfg.paths.torrents.root}
        chmod g+s ${cfg.paths.torrents.books}
        chmod g+s ${cfg.paths.torrents.movies}
        chmod g+s ${cfg.paths.torrents.music}
        chmod g+s ${cfg.paths.torrents.tv}

        # Usenet directories
        chmod g+s ${cfg.paths.usenet.root}
        chmod g+s ${cfg.paths.usenet.incomplete}
        chmod g+s ${cfg.paths.usenet.complete.root}
        chmod g+s ${cfg.paths.usenet.complete.books}
        chmod g+s ${cfg.paths.usenet.complete.movies}
        chmod g+s ${cfg.paths.usenet.complete.music}
        chmod g+s ${cfg.paths.usenet.complete.tv}

        # Media library directories
        chmod g+s ${cfg.paths.media.root}
        chmod g+s ${cfg.paths.media.books}
        chmod g+s ${cfg.paths.media.movies}
        chmod g+s ${cfg.paths.media.music}
        chmod g+s ${cfg.paths.media.tv}

        # Ensure group write permissions (2775 = sticky + rwxrwxr-x)
        chmod 2775 ${cfg.baseDir}

        chmod 2775 ${cfg.paths.torrents.root}
        chmod 2775 ${cfg.paths.torrents.books}
        chmod 2775 ${cfg.paths.torrents.movies}
        chmod 2775 ${cfg.paths.torrents.music}
        chmod 2775 ${cfg.paths.torrents.tv}

        chmod 2775 ${cfg.paths.usenet.root}
        chmod 2775 ${cfg.paths.usenet.incomplete}
        chmod 2775 ${cfg.paths.usenet.complete.root}
        chmod 2775 ${cfg.paths.usenet.complete.books}
        chmod 2775 ${cfg.paths.usenet.complete.movies}
        chmod 2775 ${cfg.paths.usenet.complete.music}
        chmod 2775 ${cfg.paths.usenet.complete.tv}

        chmod 2775 ${cfg.paths.media.root}
        chmod 2775 ${cfg.paths.media.books}
        chmod 2775 ${cfg.paths.media.movies}
        chmod 2775 ${cfg.paths.media.music}
        chmod 2775 ${cfg.paths.media.tv}
      '';
    };
  };
}
