{
  config,
  pkgs,
  ...
}: let
  hosts = import ../../hosts.nix;
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
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

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
    signupsAllowed = false;
    invitationsAllowed = true;
    # To enable admin panel, create environment file with ADMIN_TOKEN:
    # environmentFile = "/run/secrets/vaultwarden-env";
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

  # Custom gallery-dl from Gitea fork
  fleet.apps.galleryDl = {
    enable = true;

    instances.telegram = {
      enable = true;
      # every minute
      onCalendar = "minutely";

      # Render config from Nix attrset + sops secrets (no external template file)
      workingDir = "/data/archive/telegram";
      # We use Postgres-backed archive via `extractor.archive` in config;
      # do not override it with `--download-archive <file>`.
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "/data/archive";
          archive = "@ARCHIVE_URL@";
          telegram = {
            "api-id" = "@TG_API_ID@";
            "api-hash" = "@TG_API_HASH@";
            "session-type" = "string";
            "session-string" = "@TG_SESSION_STRING@";
            download = [
              "messages"
              "stories"
              "text"
              "posts"
              "profile_pictures"
            ];
            "avatar-size" = [64 64];
            "media-mime-types" = [];
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
      urlFile = "/data/archive/telegram/urls.txt";

      # Add your preferred args here:
      args = ["--write-metadata"];
    };

    instances.telegramReplies = {
      enable = true;
      onCalendar = "minutely";

      workingDir = "/data/archive/telegram";
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "/data/archive";
          archive = "@ARCHIVE_URL@";
          telegram = {
            "api-id" = "@TG_API_ID@";
            "api-hash" = "@TG_API_HASH@";
            "session-type" = "string";
            "session-string" = "@TG_SESSION_STRING@";
            download = [
              "replies"
              "text"
            ];
            "avatar-size" = [64 64];
            "media-mime-types" = [];
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
      urlFile = "/data/archive/telegram/urls.txt";

      # Add your preferred args here:
      args = ["--write-metadata"];
    };

    instances.boosty = {
      enable = true;
      onCalendar = "hourly";

      workingDir = "/data/archive/boosty";
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "/data/archive";
          archive = "@ARCHIVE_URL@";
        };
      };
      configSubstitutions = {
        "@ARCHIVE_URL@" = config.sops.secrets."gallery-dl/archive-url".path;
      };

      # one URL per line
      urlFile = "/data/archive/boosty/urls.txt";

      # Add your preferred args here:
      args = ["--cookies=/data/archive/boosty/cookies.txt" "--write-metadata"];
    };

    instances.twitter = {
      enable = true;
      onCalendar = "minutely";

      workingDir = "/data/archive/twitter";
      useDownloadArchiveFile = false;
      config = {
        extractor = {
          "base-directory" = "/data/archive";
          archive = "@ARCHIVE_URL@";
        };
      };
      configSubstitutions = {
        "@ARCHIVE_URL@" = config.sops.secrets."gallery-dl/archive-url".path;
      };

      # one URL per line
      urlFile = "/data/archive/twitter/urls.txt";

      # Add your preferred args here:
      args = ["--cookies=/data/archive/twitter/cookies.txt" "--write-metadata"];
    };
  };

  # --------------------------------------------------------------------------
  # /data/archive permissions (requested)
  # WARNING: this makes everything under /data/archive world-readable + writable.
  # --------------------------------------------------------------------------

  systemd.services.data-archive-permissions = {
    description = "Force /data/archive permissions to 0777 recursively (requested)";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    restartIfChanged = false;

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };

    script = ''
      set -euo pipefail
      chmod -R 0777 /data/archive
    '';
  };

  # Ensure /data/archive paths exist for gallery-dl
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

  fleet.media.shared = {
    enable = true;
    baseDir = "/data";
    # Directory structure:
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
  # MEDIA SERVICES
  # ============================================================================

  # Jellyfin - Media streaming server
  fleet.media.jellyfin = {
    enable = true;
    domain = "jellyfin.sn0wstorm.com";
    # Uses default: sharedCfg.paths.media.root (/data/media)
    hardwareAcceleration = {
      enable = true;
      type = "amd"; # AMD VAAPI for hardware transcoding
    };
  };

  # Sonarr - TV series management
  fleet.media.sonarr = {
    enable = true;
    domain = "sonarr.sn0wstorm.com";
  };

  # Radarr - Movie management
  fleet.media.radarr = {
    enable = true;
    domain = "radarr.sn0wstorm.com";
  };

  # Lidarr - Music management
  fleet.media.lidarr = {
    enable = true;
    domain = "lidarr.sn0wstorm.com";
  };

  # Readarr - Ebook management
  fleet.media.readarr = {
    enable = true;
    domain = "readarr.sn0wstorm.com";
  };

  # Prowlarr - Indexer management
  fleet.media.prowlarr = {
    enable = true;
    domain = "prowlarr.sn0wstorm.com";
  };

  # Bazarr - Subtitle management
  fleet.media.bazarr = {
    enable = true;
    domain = "bazarr.sn0wstorm.com";
  };

  # Overseerr - Media request management
  fleet.media.overseerr = {
    enable = true;
    domain = "overseerr.sn0wstorm.com";
  };

  # ============================================================================
  # VPN GATEWAY (Gluetun with PIA)
  # ============================================================================

  fleet.networking.vpnGateway = {
    enable = true;
    provider = "private_internet_access";

    pia = {
      # Regions that support port forwarding
      serverRegions = ["Czech Republic" "FI Helsinki"];
      portForwarding = true;
      usernameFile = "/run/secrets/pia-vpn/username";
      passwordFile = "/run/secrets/pia-vpn/password";
    };

    killSwitch = true;
  };

  # ============================================================================
  # SAMBA SHARE FOR /data
  # ============================================================================

  fleet.networking.sambaDataShare = {
    enable = true;
    shareName = "data";
    path = "/data";
    usernameFile = config.sops.secrets."samba/data/username".path;
    passwordFile = config.sops.secrets."samba/data/password".path;
    allowedNetworks = ["192.168.2.0/24" "127.0.0.1"];
    openFirewall = true;
    wsdd.enable = true;
  };

  # qBittorrent - Torrent client (VPN protected)
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
    enable = true;
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
    allowedCIDRs = ["192.168.2.0/24"];

    ssl = {
      enable = true;
      require = true;
      certFile = "/var/lib/postgresql/16/server.crt";
      keyFile = "/var/lib/postgresql/16/server.key";
    };
  };

  # ============================================================================
  # CLOUDFLARE DYNAMIC DNS SERVICE
  # ============================================================================

  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = "/run/secrets/cloudflare_api_token";
    domains = ["sn0wstorm.com"];
  };

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
      "jellyfin.sn0wstorm.com"
      "navidrome.sn0wstorm.com"
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

    # Domains where /api/* bypasses auth (for *arr apps)
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
  };

  # ============================================================================
  # BACKUP CONFIGURATION
  # ============================================================================

  fleet.system.backupVarLib = {
    enable = true;
    schedule = "daily";
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

      # gallery-dl (telegram) secrets used to render config.json at runtime
      "gallery-dl/archive-url" = {
        owner = config.fleet.apps.galleryDl.user;
        group = config.fleet.apps.galleryDl.group;
        mode = "0400";
      };
      "gallery-dl/telegram/api-id" = {
        owner = config.fleet.apps.galleryDl.user;
        group = config.fleet.apps.galleryDl.group;
        mode = "0400";
      };
      "gallery-dl/telegram/api-hash" = {
        owner = config.fleet.apps.galleryDl.user;
        group = config.fleet.apps.galleryDl.group;
        mode = "0400";
      };
      "gallery-dl/telegram/session-string" = {
        owner = config.fleet.apps.galleryDl.user;
        group = config.fleet.apps.galleryDl.group;
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

      # Hetzner SMB backup credentials
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

      # Samba /data share credentials
      "samba/data/username" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
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

  # Ensure dominik's directories (and /data/archive paths) exist
  systemd.tmpfiles.rules = [
    # gallery-dl base
    "d /data/archive 0777 root root -"
    "d /data/archive/telegram 0777 root root -"
    "f /data/archive/telegram/urls.txt 0666 root root -"
    "d /data/archive/boosty 0777 root root -"
    "f /data/archive/boosty/urls.txt 0666 root root -"

    # Nextcloud data directory
    "d /data/nextcloud 0750 nextcloud nextcloud -"
    "d /data/nextcloud/apps 0750 nextcloud nextcloud -"

    "d /home/dominik/.ssh 0700 dominik users"
    "d /home/dominik/.config 0755 dominik users -"
    "d /home/dominik/.config/sops 0755 dominik users -"
    "d /home/dominik/.config/sops/age 0755 dominik users -"
  ];

  # ============================================================================

  # Network interface
  networking = {
    useDHCP = false;
    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = hosts.galadriel.ip;
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "192.168.2.1";
    nameservers = ["8.8.8.8" "1.1.1.1"];
  };

  networking.firewall.allowedTCPPorts = [];

  # ============================================================================
  # SMB/CIFS MOUNTS
  # ============================================================================

  # Required for mounting CIFS/SMB shares
  environment.systemPackages = [pkgs.cifs-utils];

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
