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

  # Temporarily disable SSL until certificates are generated
  # fleet.networking.reverseProxy = {
  #   enable = true;
  #   enableTLS = true;
  #   enableACME = true;
  #   acmeEmail = "dominik@example.com";
  # };

  fleet.networking.reverseProxy = {
    enable = true;
    enableTLS = false;  # Disable SSL temporarily
    enableACME = true;
    acmeEmail = "dominik@example.com";
  };

  # Ensure services start in correct order
  systemd.services.acme-sn0wstorm-com = {
    wants = ["cloudflare-acme-credentials.service"];
    after = ["cloudflare-acme-credentials.service"];
  };

  systemd.services.nginx = {
    wants = ["acme-sn0wstorm-com.service"];
    after = ["acme-sn0wstorm-com.service"];
  };

  # Service to enable SSL once certificates are ready
  systemd.services.enable-ssl-after-acme = {
    description = "Enable SSL in nginx after ACME certificates are generated";
    wantedBy = ["multi-user.target"];
    after = ["acme-sn0wstorm-com.service" "nginx.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Wait for certificate to exist
      timeout=300  # 5 minutes
      count=0
      while [ ! -f /var/lib/acme/sn0wstorm.com/fullchain.pem ] && [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
      done

      if [ -f /var/lib/acme/sn0wstorm.com/fullchain.pem ]; then
        echo "ACME certificates found, you can now enable SSL by uncommenting the reverse proxy TLS config and running: nixos-rebuild switch"
      else
        echo "ACME certificates not found after timeout, check ACME service logs with: journalctl -u acme-sn0wstorm-com.service"
      fi
    '';
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

  # Create SSL enable flag based on certificate existence
  systemd.services.ssl-status-check = {
    description = "Check if SSL certificates exist and create status file";
    wantedBy = ["multi-user.target"];
    before = ["nginx.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      mkdir -p /var/lib/fleet-ssl-status
      if [ -f /var/lib/acme/sn0wstorm.com/fullchain.pem ]; then
        echo "true" > /var/lib/fleet-ssl-status/enable
      else
        echo "false" > /var/lib/fleet-ssl-status/enable
      fi
      chmod 644 /var/lib/fleet-ssl-status/enable
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
