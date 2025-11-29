{
  config,
  pkgs,
  pinnedPkgs ? pkgs, # Fallback to regular pkgs if not provided
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
    # Monitoring
    ../../modules/monitoring/prometheus.nix
    ../../modules/monitoring/grafana.nix
    # Dev
    ../../modules/dev/jenkins.nix
    # Apps
    ../../modules/apps/homepage.nix
    ../../modules/apps/vaultwarden.nix
    # Media
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
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "galadriel";

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.dev.jenkins.enable = true;

  # Vaultwarden Password Manager
  fleet.apps.vaultwarden = {
    enable = true;
    domain = "bitwarden.sn0wstorm.com";
    signupsAllowed = false;
    invitationsAllowed = true;
    # To enable admin panel, create environment file with ADMIN_TOKEN:
    # environmentFile = "/run/secrets/vaultwarden-env";
  };

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

  # ============================================================================
  # MEDIA SERVICES
  # ============================================================================

  # Jellyfin - Media streaming server
  fleet.media.jellyfin = {
    enable = true;
    domain = "jellyfin.sn0wstorm.com";
    mediaDir = "/media";
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

  # qBittorrent - Torrent client
  fleet.media.qbittorrent = {
    enable = true;
    domain = "qbittorrent.sn0wstorm.com";
    downloadDir = "/media/downloads";
  };


  fleet.media.sabnzbd = {
    enable = true;
    domain = "sabnzbd.sn0wstorm.com";
    package = pinnedPkgs.sabnzbd;
  };

  # Navidrome - Music streaming server
  fleet.media.navidrome = {
    enable = true;
    domain = "navidrome.sn0wstorm.com";
    musicFolder = "/media/music";
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

    defaultPolicy = "one_factor";

    bypassDomains = [
      "bitwarden.sn0wstorm.com"
      "jellyfin.sn0wstorm.com"
      "navidrome.sn0wstorm.com"
    ];

    bypassPaths = [
      "/api/**"
      "/.well-known/**"
    ];

    twoFactorDomains = [
      "grafana.sn0wstorm.com"
      "prometheus.sn0wstorm.com"
    ];

    secrets = {
      jwtSecretFile = "/run/secrets/authelia_jwt_secret";
      storageEncryptionKeyFile = "/run/secrets/authelia_storage_key";
    };

    usersFile = "/run/secrets/authelia_users";

    sessionDomain = "sn0wstorm.com";
    sessionExpiration = "12h";
    sessionInactivity = "45m";
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
      "git_user_name" = {};
      "git_user_email" = {};

      # Authelia secrets
      "authelia_jwt_secret" = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };
      "authelia_storage_key" = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };
      "authelia_users" = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };
    };
  };

  # ============================================================================
  # SOPS AGE KEY DIRECTORY
  # ============================================================================

  # Ensure dominik's directories exist
  systemd.tmpfiles.rules = [
    "d /home/dominik/.ssh 0700 dominik users"
    "d /home/dominik/.config 0755 dominik users -"
    "d /home/dominik/.config/sops 0755 dominik users -"
    "d /home/dominik/.config/sops/age 0755 dominik users -"
  ];

  # ============================================================================

  networking = {
    useDHCP = false;
    interfaces.ens18 = {
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
  # GIT CONFIGURATION
  # ============================================================================

  # Git configuration with fallback identity
  programs.git.enable = true;

  # Git identity from secrets:
  programs.git.config = {
    user = {
      name = "$(cat /run/secrets/git_user_name)";
      email = "$(cat /run/secrets/git_user_email)";
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
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  system.stateVersion = "25.05";
}
