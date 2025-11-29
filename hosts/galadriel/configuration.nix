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
  # DNS SERVER (BIND) WITH RFC2136 SUPPORT
  # ============================================================================

  services.bind = {
    enable = true;
    extraConfig = ''
      include "/var/lib/secrets/dnskeys.conf";
    '';
    zones = [
      rec {
        name = "sn0wstorm.com";
        file = "/var/db/bind/${name}";
        master = true;
        extraConfig = "allow-update { key rfc2136key.sn0wstorm.com.; };";
      }
    ];
  };

  # ============================================================================
  # RFC2136 TSIG KEY GENERATION
  # ============================================================================

  systemd.services.dns-rfc2136-conf = {
    requiredBy = [
      "acme-sn0wstorm.com.service"
      "bind.service"
    ];
    before = [
      "acme-sn0wstorm.com.service"
      "bind.service"
    ];
    unitConfig = {
      ConditionPathExists = "!/var/lib/secrets/dnskeys.conf";
    };
    serviceConfig = {
      Type = "oneshot";
      UMask = 77;
    };
    path = [ pkgs.bind ];
    script = ''
      mkdir -p /var/lib/secrets
      chmod 755 /var/lib/secrets
      tsig-keygen rfc2136key.sn0wstorm.com > /var/lib/secrets/dnskeys.conf
      chown named:root /var/lib/secrets/dnskeys.conf
      chmod 400 /var/lib/secrets/dnskeys.conf

      # extract secret value from the dnskeys.conf
      while read x y; do if [ "$x" = "secret" ]; then secret="''${y:1:''${#y}-3}"; fi; done < /var/lib/secrets/dnskeys.conf

      cat > /var/lib/secrets/certs.secret << EOF
      RFC2136_NAMESERVER='127.0.0.1:53'
      RFC2136_TSIG_ALGORITHM='hmac-sha256.'
      RFC2136_TSIG_KEY='rfc2136key.sn0wstorm.com'
      RFC2136_TSIG_SECRET='$secret'
      EOF
      chmod 400 /var/lib/secrets/certs.secret
    '';
  };

  # ============================================================================
  # ACME WITH DNS-01 VALIDATION
  # ============================================================================

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "dominik@example.com";
  security.acme.defaults = {
    dnsProvider = "rfc2136";
    environmentFile = "/var/lib/secrets/certs.secret";
    # We don't need to wait for propagation since this is a local DNS server
    dnsPropagationCheck = false;
  };

  # ============================================================================
  # REVERSE PROXY (Pluggable - services register themselves automatically)
  # ============================================================================

  fleet.networking.reverseProxy = {
    enable = true;
    enableTLS = true;   # Enable TLS since nginx will handle ACME
    enableACME = true;  # Use nginx's built-in ACME with DNS validation
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
