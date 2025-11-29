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
    ../../modules/monitoring/prometheus.nix
    ../../modules/monitoring/grafana.nix
    ../../modules/dev/jenkins.nix
    ../../modules/apps/cloudflare-ddns.nix
    ../../modules/networking/reverse-proxy.nix
    ../../modules/security/self-signed-ca.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "galadriel";
  users.motd = "Galadriel";

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.dev.jenkins.enable = true;

  fleet.apps.cloudflare-ddns = {
    enable = true;
    apiTokenFile = "/run/secrets/cloudflare_api_token";
    zoneIdFile = "/run/secrets/cloudflare_zone_id";
    recordName = "sn0wstorm.com";
    recordType = "A";
    interval = "5min";
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
    domain = hosts.galadriel.ip;
    prometheusUrl = "http://localhost:9090";
  };

  # --------------------------------------------------------------------------
  # TLS CERTIFICATES
  # --------------------------------------------------------------------------

  fleet.security.selfSignedCA = {
    enable = true;
    caName = "Fleet Internal CA";
    domains = [
      "jenkins.local"
      "grafana.local"
      "prometheus.local"
      "git.local"
      "rss.local"
    ];
  };

  # --------------------------------------------------------------------------
  # REVERSE PROXY
  # --------------------------------------------------------------------------

  fleet.networking.reverseProxy = {
    enable = true;
    enableTLS = true;
    routes = {
      "jenkins.local" = {
        target = hosts.galadriel.ip;
        port = 8080;
        description = "Jenkins CI/CD";
      };
      "grafana.local" = {
        target = hosts.galadriel.ip;
        port = 3000;
        description = "Grafana monitoring dashboard";
      };
      "prometheus.local" = {
        target = hosts.galadriel.ip;
        port = 9090;
        description = "Prometheus metrics";
      };
      "git.local" = {
        target = hosts.frodo.ip;
        port = 3000;
        description = "Gitea repository hosting";
        extraConfig = ''
          client_max_body_size 500M;
          proxy_read_timeout 300;
          proxy_send_timeout 300;
        '';
      };
      "rss.local" = {
        target = hosts.sam.ip;
        port = 8080;
        description = "FreshRSS feed aggregator";
      };
    };
  };

  # ============================================================================
  # SECRETS MANAGEMENT (SOPS-NIX)
  # ============================================================================

  # SOPS configuration for encrypted secrets
  sops = {
    # Default secrets location
    defaultSopsFile = ../../secrets/galadriel.yaml;

    # Age key for decryption (this should match your .sops.yaml)
    age.keyFile = "/home/dominik/.config/sops/age/keys.txt";

    # SOPS secrets
    secrets = {
      # Cloudflare DDNS secrets
      "cloudflare_api_token" = {};
      "cloudflare_zone_id" = {};
    };
  };

  # --------------------------------------------------------------------------
  # SOPS AGE KEY DIRECTORY
  # --------------------------------------------------------------------------

  # Ensure dominik's SOPS directory exists
  systemd.tmpfiles.rules = [
    "d /home/dominik/.config 0755 dominik users -"
    "d /home/dominik/.config/sops 0755 dominik users -"
    "d /home/dominik/.config/sops/age 0755 dominik users -"
  ];

  # --------------------------------------------------------------------------

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
