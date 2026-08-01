{
  config,
  lib,
  pkgs,
  ...
}: let
  hosts = import ../../hosts.nix;
  hetznerMount = "/mnt/hetzner";
  archiveBase = "${hetznerMount}/archive";
  galleryDlAfterMount = [
    "gallery-dl-telegram.service"
    "gallery-dl-telegramReplies.service"
    "gallery-dl-boosty.service"
    "gallery-dl-twitter.service"
    "gallery-dl-twitterDm.service"
    "gallery-dl-telegram-channel-list.service"
    "gallery-dl-twitter-following-list.service"
    "gallery-dl-job-telegram.service"
    "gallery-dl-job-telegramReplies.service"
    "gallery-dl-job-boosty.service"
    "gallery-dl-job-twitter.service"
    "gallery-dl-job-twitterDm.service"
  ];
  archiveMountConsumers =
    galleryDlAfterMount
    ++ [
      "media-permissions.service"
      "data-archive-permissions.service"
      "podman-gluetun.service"
      "podman-qbittorrent.service"
      "qbittorrent-credentials.service"
      "qbittorrent-config.service"
      "sabnzbd.service"
      "sonarr.service"
      "radarr.service"
      "lidarr.service"
      "readarr.service"
      "prowlarr.service"
      "bazarr.service"
    ];
in {
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    # Security
    ../../modules/security/acme.nix
    ../../modules/security/authelia.nix
    # Networking
    ../../modules/networking/reverse-proxy.nix
    ../../modules/networking/vpn-gateway.nix
    ../../modules/networking/samba.nix
    ../../modules/networking/tailscale.nix
    # Monitoring
    ../../modules/monitoring/prometheus.nix
    ../../modules/monitoring/grafana.nix
    # Dev
    ../../modules/dev/gitea.nix
    ../../modules/dev/jenkins.nix
    # Apps
    ../../modules/apps/homepage.nix
    ../../modules/apps/mysql.nix
    ../../modules/apps/postgresql.nix
    ../../modules/apps/vaultwarden.nix
    ../../modules/apps/gallery-dl.nix
    ../../modules/apps/cockpit.nix
    ../../modules/apps/nextcloud.nix
    ../../modules/apps/fredy.nix
    # Media
    ../../modules/media/shared-media.nix
    ../../modules/media/jellyfin.nix
    ../../modules/media/sonarr.nix
    ../../modules/media/radarr.nix
    ../../modules/media/lidarr.nix
    ../../modules/media/readarr.nix
    ../../modules/media/prowlarr.nix
    ../../modules/media/bazarr.nix
    ../../modules/media/overseerr.nix
    ../../modules/media/qbittorrent.nix
    ../../modules/media/transmission.nix
    ../../modules/media/sabnzbd.nix
    ../../modules/media/navidrome.nix
    ../../modules/media/configarr.nix
    # System
    ../../modules/system/backup-var-lib.nix
    ../../modules/system/hetzner-archive-mount.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  system.activationScripts.nixGiteaNetrc = {
    deps = ["setupSecrets"];
    text = ''
          TOKEN="$(cat ${config.sops.secrets."gitea/nix-fetch-token".path})"
          install -D -m 600 /dev/null /root/.netrc
          cat > /root/.netrc <<EOF
      machine git.sn0wstorm.com
      login Dominik
      password ''${TOKEN}
      EOF
    '';
  };

  networking.hostName = "galadriel";

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.dev.jenkins.enable = true;

  fleet.dev.gitea = {
    enable = true;
    domain = "git.sn0wstorm.com";
    # Avoid collision with Grafana (also defaults to 3000)
    port = 3001;
    appName = "Fleet Git";
    disableRegistration = true;
    requireSigninView = true;

    # This host runs Gitea behind nginx reverse proxy + TLS
    listenAddress = "127.0.0.1";
    openFirewall = false;
    bypassAuth = true;

    # Match the old Docker layout under /data:
    # - /data/gitea (attachments/avatars/sessions/logs/...)
    # - /data/git (repositories + lfs)
    paths = {
      appDataPath = "/var/lib/gitea/gitea";
      repositoryRoot = "/var/lib/gitea/git/repositories";
      lfsPath = "/var/lib/gitea/git/lfs";
    };

    database = {
      type = "mysql";
      mysql.useFleetMysql = true;
    };
  };

  # Vaultwarden Password Manager
  fleet.apps.vaultwarden = {
    enable = true;
    domain = "bitwarden.sn0wstorm.com";
    signupsAllowed = true;
    invitationsAllowed = true;
    # SMTP: host in config (avoids secret encoding), password from secret
    smtp = {
      enable = true;
      from = "bitwarden@sn0wstorm.com";
      host = "mail.sn0wstorm.com";
      passwordFile = config.sops.secrets."bitwarden/smtp-password".path;
      port = 587;
      security = "starttls";
    };
    adminTokenFile = config.sops.secrets."bitwarden/admin_token".path;
  };

  # Nextcloud - File sync and sharing platform
  fleet.apps.nextcloud = {
    enable = true;
    domain = "cloud.sn0wstorm.com";
    database = {
      type = "mysql";
      mysql.useFleetMysql = true;
    };
  };

  # Hetzner Storage Box — downloader and gallery-dl archive tree
  fleet.system.hetznerArchiveMount = {
    enable = true;
    mountPoint = hetznerMount;
    archiveSubdir = "archive";
    afterMountServices = archiveMountConsumers;
  };

  # Fredy - German real estate search automation
  fleet.apps.fredy = {
    enable = false;
    domain = "immo.sn0wstorm.com";
  };

  # Custom gallery-dl from Gitea fork (downloads to Hetzner archive share)
  fleet.apps.galleryDl = {
    enable = true;
    archiveDir = archiveBase;

    instances.telegram = {
      enable = true;
      # every minute
      onCalendar = "minutely";

      # Render config from Nix attrset + sops secrets (no external template file)
      workingDir = "${archiveBase}/telegram";
      # We use Postgres-backed archive via `extractor.archive` in config;
      # do not override it with `--download-archive <file>`.
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "${archiveBase}";
          archive = "@ARCHIVE_URL@";
          telegram = {
            "api-id" = "@TG_API_ID@";
            "api-hash" = "@TG_API_HASH@";
            "session-type" = "string";
            "session-string" = "@TG_SESSION_STRING@";
            download = [
              "messages"
              "stories"
              "media"
              "text"
              "posts"
              "profile_pictures"
            ];
            "avatar-size" = [64 64];
            "batch-size" = 2000;
            "order-messages" = "desc";
            limit = null;
          };
        };
      };
      configSubstitutions = {
        "@ARCHIVE_URL@" = config.sops.secrets."gallery-dl/archive-url".path;
        "@TG_API_ID@" = config.sops.secrets."gallery-dl/telegram/api-id".path;
        "@TG_API_HASH@" = config.sops.secrets."gallery-dl/telegram/api-hash".path;
        "@TG_SESSION_STRING@" = config.sops.secrets."gallery-dl/telegram/session-string".path;
      };

      # one URL per line
      urlFile = "${archiveBase}/telegram/urls.txt";

      # Add your preferred args here:
      args = ["--write-metadata"];
    };

    # Update urls.txt with all Telegram channels the account is part of (every 10 minutes).
    telegramChannelList = {
      urlFile = "${archiveBase}/telegram/urls.txt";
      urlLogFile = "${archiveBase}/telegram/url-logs.txt";
      apiIdPath = config.sops.secrets."gallery-dl/telegram/api-id".path;
      apiHashPath = config.sops.secrets."gallery-dl/telegram/api-hash".path;
      sessionStringPath = config.sops.secrets."gallery-dl/telegram/session-string".path;
      onCalendar = "*-*-* *:0/10:00";
    };

    instances.telegramReplies = {
      enable = true;
      onCalendar = "minutely";

      workingDir = "${archiveBase}/telegram";
      renderedConfigFileName = "config-replies.json";
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "${archiveBase}";
          archive = "@ARCHIVE_URL@";
          telegram = {
            "api-id" = "@TG_API_ID@";
            "api-hash" = "@TG_API_HASH@";
            "session-type" = "string";
            "session-string" = "@TG_SESSION_STRING@";
            download = [
              "replies"
              "media"
              "text"
            ];
            "avatar-size" = [64 64];
            "batch-size" = 2000;
            "order-messages" = "desc";
            limit = null;
          };
        };
      };
      configSubstitutions = {
        "@ARCHIVE_URL@" = config.sops.secrets."gallery-dl/archive-url".path;
        "@TG_API_ID@" = config.sops.secrets."gallery-dl/telegram/api-id".path;
        "@TG_API_HASH@" = config.sops.secrets."gallery-dl/telegram/api-hash".path;
        "@TG_SESSION_STRING@" = config.sops.secrets."gallery-dl/telegram/session-string".path;
      };

      # one URL per line (same as main telegram instance)
      urlFile = "${archiveBase}/telegram/urls.txt";

      # Add your preferred args here:
      args = ["--write-metadata"];
    };

    instances.boosty = {
      enable = true;
      onCalendar = "hourly";

      workingDir = "${archiveBase}/boosty";
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "${archiveBase}";
          archive = "@ARCHIVE_URL@";
          twitter.messages.pin = "@TWITTER_DM_PIN@";
        };
      };
      configSubstitutions = {
        "@ARCHIVE_URL@" = config.sops.secrets."gallery-dl/archive-url".path;
        "@TWITTER_DM_PIN@" = config.sops.secrets."gallery-dl/twitter-messages-pin".path;
      };

      # one URL per line
      urlFile = "${archiveBase}/boosty/urls.txt";

      # Add your preferred args here:
      args = ["--cookies=${archiveBase}/boosty/cookies.txt" "--write-metadata"];
    };

    instances.twitter = {
      enable = true;
      onCalendar = "*-*-* *:0/30:00";
      pruneEmptyDownloads = true;

      workingDir = "${archiveBase}/twitter";
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "${archiveBase}";
          archive = "@ARCHIVE_URL@";
          skip = "abort:10";
        };
      };
      configSubstitutions = {
        "@ARCHIVE_URL@" = config.sops.secrets."gallery-dl/archive-url".path;
      };

      # one URL per line
      urlFile = "${archiveBase}/twitter/urls.txt";

      # Add your preferred args here:
      args = ["--cookies=${archiveBase}/twitter/cookies.txt" "--write-metadata"];
    };

    instances.twitterDm = {
      enable = true;
      onCalendar = "hourly";
      renderedConfigFileName = "config-dm.json";
      pruneEmptyDownloads = true;

      workingDir = "${archiveBase}/twitter";
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "${archiveBase}";
          archive = "@ARCHIVE_URL@";
          twitter.messages.pin = "@TWITTER_DM_PIN@";
        };
      };
      configSubstitutions = {
        "@ARCHIVE_URL@" = config.sops.secrets."gallery-dl/archive-url".path;
        "@TWITTER_DM_PIN@" = config.sops.secrets."gallery-dl/twitter-messages-pin".path;
      };

      urls = ["https://x.com/messages"];

      argsBeforeMtime = [
        "--cookies"
        "${archiveBase}/twitter/cookies.txt"
      ];

      args = [
        "--write-metadata"
        "-O"
        "event=file"
        "-O"
        "mtime=true"
        "-o"
        "extractor.twitter.messages.directory=[\"{category}\",\"{user[name]}\",\"DMs\"]"
      ];
    };

    twitterFollowingList = {
      urlFile = "${archiveBase}/twitter/urls.txt";
      urlLogFile = "${archiveBase}/twitter/url-logs.txt";
      cookiesPath = "${archiveBase}/twitter/cookies.txt";
      twitterUsername = "Siad0n";
      onCalendar = "hourly"; # toned down from every 10 min
    };
  };

  # --------------------------------------------------------------------------
  # ${archiveBase} permissions baseline.
  # --------------------------------------------------------------------------

  # CIFS archive permissions come from hetzner-archive-mount (dir_mode/file_mode).
  # Recursive chmod over SMB is slow and blocks nixos-rebuild for 15+ minutes.
  systemd.services.data-archive-permissions.enable = false;

  # Keep Twitter archive tree SMB-readable after each run (DM downloads can
  # create nested files with restrictive permissions depending on process umask).
  # With 0755, only the owner can write, so ensure twitter tree ownership is
  # normalized to the gallery-dl service user before each run.
  systemd.services.gallery-dl-job-twitter.serviceConfig.ExecStartPre = [
    "+${pkgs.coreutils}/bin/chown -R ${config.fleet.apps.galleryDl.user}:${config.fleet.apps.galleryDl.group} ${archiveBase}/twitter"
    "+${pkgs.coreutils}/bin/chmod -R 0755 ${archiveBase}/twitter"
  ];
  systemd.services.gallery-dl-job-twitter.serviceConfig.TimeoutStartSec = "3h";
  systemd.services.gallery-dl-job-twitter.serviceConfig.UMask = "0022";
  systemd.services.gallery-dl-job-twitter.serviceConfig.ExecStartPost = [
    "${pkgs.coreutils}/bin/chmod -R 0755 ${archiveBase}/twitter"
  ];
  systemd.services.gallery-dl-job-twitterDm.serviceConfig.ExecStartPre = [
    "+${pkgs.coreutils}/bin/chown -R ${config.fleet.apps.galleryDl.user}:${config.fleet.apps.galleryDl.group} ${archiveBase}/twitter"
    "+${pkgs.coreutils}/bin/chmod -R 0755 ${archiveBase}/twitter"
  ];
  systemd.services.gallery-dl-job-twitterDm.serviceConfig.TimeoutStartSec = "2h";
  systemd.services.gallery-dl-job-twitterDm.serviceConfig.UMask = "0022";
  systemd.services.gallery-dl-job-twitterDm.serviceConfig.ExecStartPost = [
    "${pkgs.coreutils}/bin/chmod -R 0755 ${archiveBase}/twitter"
  ];

  # Ensure ${archiveBase} paths exist for gallery-dl
  # NOTE: Keep all tmpfiles rules in a single assignment in this file.

  # Homepage Dashboard
  fleet.apps.homepage = {
    enable = true;
    domain = "home.sn0wstorm.com";
    title = "Fleet Dashboard";
    bookmarks = [
      {
        Developer = [
          {
            GitHub = {
              abbr = "GH";
              href = "https://github.com/";
            };
          }
          {
            NixOS = {
              abbr = "NIX";
              href = "https://nixos.org/";
            };
          }
        ];
      }
      {
        Cloud = [
          {
            Cloudflare = {
              abbr = "CF";
              href = "https://dash.cloudflare.com/";
            };
          }
        ];
      }
    ];
  };

  # Cockpit - Server management interface with 2FA
  fleet.apps.cockpit = {
    enable = true;
    domain = "galadriel.sn0wstorm.com";
  };

  # ============================================================================
  # SHARED MEDIA DIRECTORY STRUCTURE
  # ============================================================================

  # Shared media dirs on Hetzner archive share (torrents, usenet, library)
  fleet.media.shared = {
    enable = true;
    baseDir = archiveBase;
    # Directory structure (when re-enabled):
    # /data/
    # ├── torrents/
    # │   ├── incomplete/   <- qBittorrent temp path
    # │   └── complete/     <- qBittorrent save path (Sonarr/Radarr imports from here)
    # ├── usenet/
    # │   ├── incomplete/   <- SABnzbd temp path
    # │   └── complete/     <- SABnzbd complete path (per-category)
    # │       ├── books/
    # │       ├── movies/
    # │       ├── music/
    # │       └── tv/
    # ├── media/            <- Final library (Jellyfin/arr apps point here)
    #     ├── books/
    #     ├── movies/
    #     ├── music/
    #     └── tv/
    # └── archive/
    #     └── gallery-dl/   <- gallery-dl archives/output (via fleet.apps.galleryDl)
  };

  # ============================================================================
  # MEDIA SERVICES (download stack on Hetzner archive; streaming apps stay off)
  # ============================================================================

  # Jellyfin - Media streaming server
  fleet.media.jellyfin = {
    enable = false;
    domain = "jellyfin.sn0wstorm.com";
    # Uses default: sharedCfg.paths.media.root (/data/media)
    hardwareAcceleration = {
      enable = true;
      type = "amd"; # AMD VAAPI for hardware transcoding
    };
  };

  # *arr stack
  fleet.media.sonarr = {
    enable = true;
    domain = "sonarr.sn0wstorm.com";
  };

  fleet.media.radarr = {
    enable = true;
    domain = "radarr.sn0wstorm.com";
  };

  fleet.media.lidarr = {
    enable = true;
    domain = "lidarr.sn0wstorm.com";
  };

  fleet.media.readarr = {
    enable = true;
    domain = "readarr.sn0wstorm.com";
  };

  fleet.media.prowlarr = {
    enable = true;
    domain = "prowlarr.sn0wstorm.com";
  };

  fleet.media.bazarr = {
    enable = true;
    domain = "bazarr.sn0wstorm.com";
  };

  # Overseerr - Media request management
  fleet.media.overseerr = {
    enable = false;
    domain = "overseerr.sn0wstorm.com";
  };

  # ============================================================================
  # VPN GATEWAY (Gluetun with PIA)
  # ============================================================================

  fleet.networking.vpnGateway = {
    enable = true;
    provider = "private_internet_access";

    pia = {
      # Regions that support port forwarding (wider list so Gluetun can fall back if one POP fails TLS)
      serverRegions = ["Netherlands" "Czech Republic" "FI Helsinki"];
      portForwarding = true;
      usernameFile = "/run/secrets/pia-vpn/username";
      passwordFile = "/run/secrets/pia-vpn/password";
    };

    killSwitch = true;
    healthCheck.enable = false;
  };

  # ============================================================================
  # SAMBA SHARE FOR /data
  # ============================================================================

  fleet.networking.sambaDataShare = {
    enable = true;
    shareName = "data";
    path = "/data";
    username = "chef";
    passwordFile = config.sops.secrets."samba/data/password".path;
    allowedNetworks = ["192.168.178.0/24" "100.64.0.0/10" "127.0.0.1"];
    openFirewall = true;
    wsdd.enable = true;
  };

  # qBittorrent - Torrent client (VPN protected, saves to Hetzner archive)
  fleet.media.qbittorrent = {
    enable = true;
    domain = "qbittorrent.sn0wstorm.com";
    port = 9000;
    # Uses default: sharedCfg.paths.torrents.complete (/data/torrents/complete)

    # Route ALL torrent traffic through PIA VPN
    vpn = {
      enable = true;
      autoUpdatePort = true;
      # API credentials for automatic port forwarding updates
      apiUsername = "admin";
      apiPasswordFile = "/run/secrets/qbittorrent/password";
    };
  };

  fleet.media.sabnzbd = {
    enable = true;
    domain = "sabnzbd.sn0wstorm.com";
  };

  # Navidrome - Music streaming server
  fleet.media.navidrome = {
    enable = false;
    domain = "navidrome.sn0wstorm.com";
    # Uses default: sharedCfg.paths.media.music (/data/media/music)
  };

  # Configarr - TRaSH Guides configuration sync
  fleet.media.configarr = {
    enable = true;
    schedule = "daily"; # Sync once per day

    sonarr = {
      enable = true;
      url = "http://localhost:8989";
      apiKeyFile = "/run/secrets/sonarr/api-key";
    };

    radarr = {
      enable = true;
      url = "http://localhost:7878";
      apiKeyFile = "/run/secrets/radarr/api-key";
    };
  };

  # ============================================================================
  # MYSQL DATABASE SERVICE
  # ============================================================================

  fleet.apps.mysql = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 3306;

    # Database requests from services (migrated from Docker MariaDB)
    databaseRequests = {
      # Authentication & SSO
      authelia = {
        database = "authelia";
        passwordFile = "/run/secrets/authelia/database/password";
      };
      gitea = {
        database = "gitea";
        passwordFile = "/run/secrets/mysql/gitea";
      };
      keycloak = {
        database = "keycloak";
        passwordFile = "/run/secrets/mysql/keycloak";
      };

      # Cloud & Storage
      nextcloud = {
        database = "nextcloud";
        passwordFile = "/run/secrets/mysql/nextcloud";
      };
      photoprism = {
        database = "photoprism";
        passwordFile = "/run/secrets/mysql/photoprism";
      };

      # Documentation & Wiki
      bookstack = {
        database = "bookstackapp";
        passwordFile = "/run/secrets/mysql/bookstack";
      };

      # Finance
      firefly = {
        database = "firefly";
        passwordFile = "/run/secrets/mysql/firefly";
      };

      # Portfolio & Other
      photo_portfolio = {
        database = "photo_portfolio";
        passwordFile = "/run/secrets/mysql/photo_portfolio";
      };
      mama_spirit = {
        database = "mama_spirit";
        passwordFile = "/run/secrets/mysql/mama_spirit";
      };
    };

    settings = {
      mysqld = {
        innodb_buffer_pool_size = "128M";
        innodb_log_file_size = "32M";
        max_connections = 100;
        skip_name_resolve = true;
      };
    };
  };

  # ============================================================================
  # POSTGRESQL DATABASE
  # ============================================================================

  fleet.apps.postgresql = {
    enable = true;
    port = 5432;

    databases = {
      gallery_dl = {
        dbName = "gallery_dl";
        secretPrefix = "postgresql/gallery_dl";
      };
    };

    settings = {
      listen_addresses = "*";
      max_connections = 100;
      shared_buffers = "128MB";
    };

    # Allow LAN clients; all TCP auth will be forced to TLS via hostssl/hostnossl.
    allowedCIDRs = ["192.168.178.0/24"];

    ssl = {
      enable = true;
      require = true;
      certFile = "/var/lib/postgresql/16/server.crt";
      keyFile = "/var/lib/postgresql/16/server.key";
    };
  };

  # ============================================================================
  # PUBLIC DNS (Cloudflare)
  # ============================================================================
  #
  # sn0wstorm.com must point at Proxmox (178.254.38.246) for SNI passthrough to
  # galadriel — NOT at this host's home WAN IP. Do not enable cloudflare-dyndns
  # here; it will fight the Proxmox entry point and break *.sn0wstorm.com.
  #
  # To (re)apply DNS: scripts/update-cloudflare-dns.sh on galadriel.

  networking.extraHosts = ''
    178.254.38.246 sn0wstorm.com headscale.sn0wstorm.com
  '';

  fleet.monitoring.prometheus = {
    enable = true;
    nodeExporterTargets = [
      "${hosts.galadriel.ip}:9100"
      "${hosts.frodo.ip}:9100"
      "${hosts.sam.ip}:9100"
    ];
  };

  fleet.monitoring.grafana = {
    enable = true;
    prometheusUrl = "https://prometheus.sn0wstorm.com";
  };

  # ============================================================================
  # ACME WILDCARD CERTIFICATE (DNS-01 validation with Cloudflare)
  # ============================================================================
  #
  # This configures a single wildcard certificate for *.sn0wstorm.com using
  # Cloudflare DNS for ACME DNS-01 challenge validation.
  #
  # The certificate is shared by all services behind the reverse proxy.
  #

  fleet.security.acme = {
    enable = true;
    domain = "sn0wstorm.com";
    email = "dominik@sn0wstorm.com";
    dnsProvider = "cloudflare";
    credentialsFile = "/run/acme-cloudflare-credentials";
  };

  # Create ACME credentials file from existing Cloudflare token
  systemd.services.acme-cloudflare-credentials = {
    description = "Create ACME Cloudflare credentials file";
    before = ["acme-sn0wstorm.com.service"];
    requiredBy = ["acme-sn0wstorm.com.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo "CLOUDFLARE_DNS_API_TOKEN=$(cat /run/secrets/cloudflare_api_token)" > /run/acme-cloudflare-credentials
      chmod 400 /run/acme-cloudflare-credentials
    '';
  };

  # ============================================================================
  # AUTHELIA (Single Sign-On & MFA)
  # ============================================================================
  #
  # Authelia provides authentication for all services behind the reverse proxy.
  # By default, ALL domains require authentication. Services can opt-out using
  # the bypassAuth option or by adding their domain to bypassDomains.
  #

  fleet.security.authelia = {
    enable = true;
    domain = "auth.sn0wstorm.com";
    theme = "light";

    # Default policy - deny, with explicit rules for access
    defaultPolicy = "deny";

    # Domains that bypass authentication entirely (have their own auth)
    bypassDomains = [
      # Services with their own authentication
      "qbittorrent.sn0wstorm.com"
      "bitwarden.sn0wstorm.com"
      # Legacy services from Docker config
      "grocy.sn0wstorm.com"
      "photos.sn0wstorm.com"
      "keycloak.sn0wstorm.com"
      "archive.sn0wstorm.com"
      "www.sn0wstorm.com"
      "wp.sn0wstorm.com"
      "plexms.sn0wstorm.com"
      "paperless.sn0wstorm.com"
      "gitlab.sn0wstorm.com"
      "git.sn0wstorm.com"
      "registry.sn0wstorm.com"
      "pokemon.sn0wstorm.com"
      "trilium.sn0wstorm.com"
      "cloud.sn0wstorm.com"
      "immo.sn0wstorm.com"
      "onlyoffice.sn0wstorm.com"
      "bookstack.sn0wstorm.com"
      "stats.sn0wstorm.com"
      "calweb.sn0wstorm.com"
      "fhir.sn0wstorm.com"
      "po.sn0wstorm.com"
      "headscale.sn0wstorm.com"
      "mail.sn0wstorm.com"
    ];

    # Domains requiring two-factor authentication
    twoFactorDomains = [
      "claw.sn0wstorm.com"
      "grafana.sn0wstorm.com"
      "prometheus.sn0wstorm.com"
      "stash.sn0wstorm.com"
      "guac.sn0wstorm.com"
      "emby.sn0wstorm.com"
      "dozzle.sn0wstorm.com"
      "code.sn0wstorm.com"
      "heimdall.sn0wstorm.com"
      "adminer.sn0wstorm.com"
      "pmox.sn0wstorm.com"
      "headscale-admin.sn0wstorm.com"
    ];

    # Domains where /api/* bypasses auth (for *arr apps; empty while media stack is off)
    apiBypassDomains = [
      "sonarr.sn0wstorm.com"
      "radarr.sn0wstorm.com"
      "lidarr.sn0wstorm.com"
      "bazarr.sn0wstorm.com"
      "jackett.sn0wstorm.com"
      "lazy.sn0wstorm.com"
      "prowlarr.sn0wstorm.com"
      "readarr.sn0wstorm.com"
      "overseerr.sn0wstorm.com"
      "qbittorrent.sn0wstorm.com"
      "sabnzbd.sn0wstorm.com"
    ];

    # Global path bypasses (regex patterns)
    bypassPaths = [
      "^/\\.well-known/.*"
      "^/signalr/.*" # Bypass signalr websocket connections (arr apps)
    ];

    # Brute force protection
    regulation = {
      maxRetries = 3;
      findTime = "2m";
      banTime = "5m";
    };

    secrets = {
      jwtSecretFile = "/run/secrets/authelia/jwt_secret";
      storageEncryptionKeyFile = "/run/secrets/authelia/storage_key";
    };

    database = {
      enable = true;
      host = "localhost";
      port = 3306;
      database = "authelia";
      username = "authelia";
      passwordFile = "/run/secrets/authelia/database/password";
    };

    # Session settings (from Docker config)
    sessionDomain = "sn0wstorm.com";
    sessionExpiration = "12h";
    sessionInactivity = "1h";
    rememberMeDuration = "1M";

    usersFile = "/run/secrets/authelia/users";

    # SMTP configuration
    smtp = {
      enable = true;
      host = "mail.sn0wstorm.com";
      port = 587;
      username = "authelia@sn0wstorm.com";
      sender = "Authelia <authelia@sn0wstorm.com>";
      identifier = "galadriel.sn0wstorm.com";
      passwordFile = "/run/secrets/authelia/smtp/password";
      tls = {
        serverName = "mail.sn0wstorm.com";
        skipVerify = false;
        minimumVersion = "TLS1.2";
      };
    };
  };

  # ============================================================================
  # REVERSE PROXY (Pluggable - services register themselves automatically)
  # ============================================================================

  fleet.networking.reverseProxy = {
    enable = true;
    enableTLS = true;
    enableAuthelia = true; # Enable Authelia protection for all services

    routes = {
      "claw.sn0wstorm.com" = {
        target = "192.168.2.143";
        port = 18789;
        description = "Claw UI";
        ssl = true;
        bypassAuth = false;
      };
    };
  };

  # ============================================================================
  # BACKUP CONFIGURATION
  # ============================================================================

  fleet.system.backupVarLib = {
    enable = false;
    # Local Windows share (D:\Backups\Galadriel_NixOS on 192.168.178.83).
    schedule = "04:00:00";
    timeout = "24h";
    memoryMax = "4G";
    mountPoint = "/mnt/galadriel-local-backup";
    repoPath = "/mnt/galadriel-local-backup/restic";
    secrets = {
      smbShareFile = "/run/secrets/local_backup_smb/share";
      smbUsernameFile = "/run/secrets/local_backup_smb/username";
      smbPasswordFile = "/run/secrets/local_backup_smb/password";
    };
    paths = [
      "/var/lib"
      "/data"
      "/etc"
      "/home"
      "/root"
      "/nix/var"
      "/boot"
    ];
    excludes = [
      "/nix/store"
      "/mnt"
      "/var/lib/docker/overlay2"
      "/var/lib/containers/storage/overlay"
      "/var/lib/systemd/coredump"
      "**/.cache"
      "**/__pycache__"
      "*.tmp"
    ];
    retention = {
      keepDaily = 7;
      keepWeekly = 4;
      keepMonthly = 6;
    };
  };

  # ============================================================================
  # SECRETS MANAGEMENT (SOPS-NIX)
  # ============================================================================

  # SOPS configuration for encrypted secrets
  sops = {
    # Default secrets location
    defaultSopsFile = ../../secrets/secrets.yaml;

    # Age key for decryption (this should match your .sops.yaml)
    age.keyFile = "/home/dominik/.config/sops/age/keys.txt";

    # SOPS secrets
    secrets = {
      "cloudflare_api_token" = {};

      # VPN credentials for PIA (read from pia-vpn.username and pia-vpn.password in secrets.yaml)
      "pia-vpn/username" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "pia-vpn/password" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # qBittorrent API password for VPN port forwarding auto-update
      "qbittorrent/password" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # gallery-dl secrets
      "gallery-dl/archive-url" = {
        owner = "gallery-dl";
        group = "gallery-dl";
        mode = "0400";
      };
      "gallery-dl/telegram/api-id" = {
        owner = "gallery-dl";
        group = "gallery-dl";
        mode = "0400";
      };
      "gallery-dl/telegram/api-hash" = {
        owner = "gallery-dl";
        group = "gallery-dl";
        mode = "0400";
      };
      "gallery-dl/telegram/session-string" = {
        owner = "gallery-dl";
        group = "gallery-dl";
        mode = "0400";
      };
      "gallery-dl/twitter-messages-pin" = {
        owner = "gallery-dl";
        group = "gallery-dl";
        mode = "0400";
      };

      "gitea/nix-fetch-token" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Tailscale/headscale pre-auth key for joining the mesh (used by tailscaled)
      "tailscale/galadriel/auth-key" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      "ssh_key" = {
        path = "/home/dominik/.ssh/id_ed25519";
        owner = "dominik";
        group = "users";
        mode = "0600";
      };

      "ssh_key_pub" = {
        path = "/home/dominik/.ssh/id_ed25519.pub";
        owner = "dominik";
        group = "users";
        mode = "0644";
      };

      "git_identity" = {
        owner = "dominik";
        group = "users";
        mode = "0400";
      };

      "vynux_smb_credentials" = {
        owner = "dominik";
        group = "users";
        mode = "0400";
      };

      # Authelia secrets (grouped)
      "authelia/jwt_secret" = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

      "authelia/storage_key" = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

      "authelia/users" = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

      "authelia/smtp/password" = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

      "authelia/database/password" = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

      # Vaultwarden SMTP (bitwarden.smtp-address, bitwarden.smtp-password in secrets.yaml)
      "bitwarden/smtp-address" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "bitwarden/smtp-password" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "bitwarden/admin_token" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      "mysql/keycloak" = {
        owner = "mysql";
        group = "mysql";
        mode = "0400";
      };
      "mysql/nextcloud" = {
        owner = "mysql";
        group = "mysql";
        mode = "0400";
      };
      "mysql/photoprism" = {
        owner = "mysql";
        group = "mysql";
        mode = "0400";
      };
      "mysql/bookstack" = {
        owner = "mysql";
        group = "mysql";
        mode = "0400";
      };
      "mysql/firefly" = {
        owner = "mysql";
        group = "mysql";
        mode = "0400";
      };
      "mysql/photo_portfolio" = {
        owner = "mysql";
        group = "mysql";
        mode = "0400";
      };
      "mysql/mama_spirit" = {
        owner = "mysql";
        group = "mysql";
        mode = "0400";
      };
      "mysql/gitea" = {
        # Used by Gitea itself at runtime (gitea-pre-start reads this file),
        # so ensure the gitea user can read it.
        owner = "root";
        group = "gitea";
        mode = "0440";
      };

      # Nextcloud admin password
      "nextcloud/admin-password" = {
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
      };

      # Sonarr API key for Configarr
      "sonarr/api-key" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Radarr API key for Configarr
      "radarr/api-key" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # PostgreSQL credentials
      "postgresql/gallery_dl/username" = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
      };
      "postgresql/gallery_dl/password" = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
      };

      # Hetzner SMB backup credentials (legacy; backup now uses local_backup_smb)
      "hetzner_smb/share" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "hetzner_smb/username" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "hetzner_smb/password" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Local Windows SMB backup (D:\Backups\Galadriel_NixOS)
      "local_backup_smb/share" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "local_backup_smb/username" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "local_backup_smb/password" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Samba /data share credentials
      "samba/data/password" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Backup restic password
      "backup/restic/password" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Backup SMTP credentials
      "backup/smtp/username" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "backup/smtp/password" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };

  # ============================================================================
  # SOPS AGE KEY DIRECTORY
  # ============================================================================

  # Ensure dominik's directories and Nextcloud /data paths exist
  systemd.tmpfiles.rules = [
    # Nextcloud data directory (only /data tree kept on local NVMe)
    "d /data/nextcloud 0770 nextcloud users -"
    "d /data/nextcloud/apps 0770 nextcloud users -"

    "d /home/dominik/.ssh 0700 dominik users"
    "d /home/dominik/.config 0755 dominik users -"
    "d /home/dominik/.config/sops 0755 dominik users -"
    "d /home/dominik/.config/sops/age 0755 dominik users -"
  ];

  # ============================================================================

  # Network: static IP via NetworkManager only (no network-addresses-eno1).
  # The legacy networking.interfaces path restarts network-addresses-eno1 on
  # every switch and drops SSH/default route mid-activation.
  networking = {
    useDHCP = lib.mkForce false;
    networkmanager.ensureProfiles.profiles.galadriel-eno1 = {
      connection = {
        id = "galadriel-eno1";
        type = "ethernet";
        autoconnect = true;
        interface-name = "eno1";
      };
      ethernet = {};
      ipv4 = {
        method = "manual";
        address1 = "${hosts.galadriel.ip}/24,192.168.178.1";
        dns = "8.8.8.8;1.1.1.1;";
      };
    };
  };

  networking.firewall.allowedTCPPorts = [];

  # ============================================================================
  # TAILSCALE / HEADSCALE MESH
  # ============================================================================
  #
  # galadriel is 100.64.0.2 on the headscale tailnet. Proxmox's SNI passthrough
  # forwards *.sn0wstorm.com (default) to 100.64.0.2:443, so without this the
  # entire wildcard is unreachable from the internet. acceptDns is disabled so
  # MagicDNS does not override the static 8.8.8.8/1.1.1.1 resolver and the
  # public *.sn0wstorm.com -> Proxmox resolution this host relies on.
  fleet.networking.tailscale = {
    enable = true;
    hostname = "galadriel";
    authKeyFile = config.sops.secrets."tailscale/galadriel/auth-key".path;
    acceptDns = false;
    # --reset is applied by fleet.networking.tailscale recovery / autoconnect paths.
    healthCheckPeer = "100.64.0.1";
    detectWanIpChange = true;
    networkRecoveryInterval = "2min";
  };

  # After an unclean shutdown (fsck on boot), postgres recovery can hold the disk
  # busy for minutes; default systemd start timeouts are too short for jenkins/sabnzbd.
  systemd.services.jenkins.serviceConfig.TimeoutStartSec = "5min";
  systemd.services.sabnzbd.serviceConfig.TimeoutStartSec = "5min";
  systemd.services.postgresql.serviceConfig.TimeoutStartSec = "10min";

  # ============================================================================
  # SMB/CIFS MOUNTS
  # ============================================================================

  # Required for mounting CIFS/SMB shares
  environment.systemPackages = [
    pkgs.cifs-utils
    pkgs.ripgrep
  ];

  fileSystems."/mnt/nas" = {
    device = "//192.168.2.2/dataPool0";
    fsType = "cifs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "credentials=/run/secrets/vynux_smb_credentials"
      "uid=1000"
      "gid=100"
    ];
  };

  # ============================================================================
  # GIT CONFIGURATION
  # ============================================================================

  # Git configuration with fallback identity
  programs.git.enable = true;

  # Git identity from secrets:
  programs.git.config = {
    include = {
      path = "/run/secrets/git_identity";
    };
    safe = {
      directory = "/home/dominik/nix-home";
    };
  };

  # ============================================================================
  # SSH CONFIGURATION
  # ============================================================================

  # SSH client configuration for git
  programs.ssh = {
    startAgent = true;
    agentTimeout = "1h";

    extraConfig = ''
      Host github.com
        IdentityFile /home/dominik/.ssh/id_ed25519
        User git
    '';
  };

  # ============================================================================
  # BOOTLOADER (UEFI with systemd-boot)
  # ============================================================================

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  system.stateVersion = "25.05";
}
