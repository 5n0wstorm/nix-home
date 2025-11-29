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
    ../../modules/networking/reverse-proxy.nix
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
  # REVERSE PROXY (Pluggable - services register themselves automatically)
  # ============================================================================

  fleet.networking.reverseProxy = {
    enable = true;
    enableTLS = true;
    enableACME = true;
    acmeEmail = "dominik@example.com"; # Replace with your actual email
    # cloudflareCredentialsFile will auto-generate from SOPS secrets
  };

  security.acme.acceptTerms = true;

  security.acme.certs."sn0wstorm.com" = {
    domain = "*.sn0wstorm.com";
    dnsProvider = "cloudflare";
    credentialsFile = "/etc/cloudflare-credentials.ini";
    group = "nginx";
    email = "dominik@example.com";
  };

  # ----------------------------------------------------------------------------
  # CLOUDFLARE CREDENTIALS FOR ACME
  # ----------------------------------------------------------------------------

  # Generate Cloudflare credentials file for ACME from SOPS secret
  systemd.services.cloudflare-acme-credentials = {
    description = "Generate Cloudflare credentials for ACME";
    wantedBy = ["multi-user.target"];
    before = ["acme-sn0wstorm.com.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      mkdir -p /etc
      cat > /etc/cloudflare-credentials.ini << EOF
      CLOUDFLARE_DNS_API_TOKEN=$(cat /run/secrets/cloudflare_api_token)
      EOF
      chmod 600 /etc/cloudflare-credentials.ini
    '';
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
