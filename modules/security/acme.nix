{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.security.acme;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================
  #
  # This module provides ACME wildcard certificate generation using DNS validation.
  # It creates a single wildcard certificate that can be shared by all services
  # behind the reverse proxy.
  #
  # Supported DNS providers: rfc2136, cloudflare, route53, etc.
  # See: https://go-acme.github.io/lego/dns/
  #
  # Example usage:
  #   fleet.security.acme = {
  #     enable = true;
  #     domain = "example.com";
  #     email = "admin@example.com";
  #     dnsProvider = "cloudflare";
  #     credentialsFile = "/var/lib/secrets/cloudflare.env";
  #   };
  #

  options.fleet.security.acme = {
    enable = mkEnableOption "ACME wildcard certificate with DNS validation";

    domain = mkOption {
      type = types.str;
      description = "Base domain for wildcard certificate (e.g., example.com for *.example.com)";
      example = "example.com";
    };

    email = mkOption {
      type = types.str;
      description = "Email address for ACME certificate registration and notifications";
      example = "admin@example.com";
    };

    dnsProvider = mkOption {
      type = types.str;
      default = "cloudflare";
      description = ''
        DNS provider for DNS-01 challenge validation.
        Common providers: cloudflare, route53, rfc2136, digitalocean, gcloud
        See: https://go-acme.github.io/lego/dns/
      '';
      example = "cloudflare";
    };

    credentialsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to environment file containing DNS provider credentials.
        For Cloudflare: CLOUDFLARE_DNS_API_TOKEN=...
        For RFC2136: RFC2136_NAMESERVER, RFC2136_TSIG_KEY, RFC2136_TSIG_SECRET
      '';
      example = "/var/lib/secrets/dns-credentials.env";
    };

    dnsPropagationCheck = mkOption {
      type = types.bool;
      default = true;
      description = "Wait for DNS propagation before validation (disable for local DNS)";
    };

    staging = mkOption {
      type = types.bool;
      default = false;
      description = "Use Let's Encrypt staging server (for testing)";
    };

    enableRfc2136 = mkOption {
      type = types.bool;
      default = false;
      description = "Enable RFC2136 (BIND/dynamic DNS) setup with TSIG key generation";
    };

    rfc2136Zone = mkOption {
      type = types.str;
      default = cfg.domain;
      description = "Zone file path for RFC2136 (defaults to domain)";
    };

    extraDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional domain SANs to include in the certificate";
      example = ["example.com" "api.example.com"];
    };

    # Derived paths for nginx consumption
    certDir = mkOption {
      type = types.str;
      default = "/var/lib/acme/${cfg.domain}";
      description = "Directory containing the certificate files";
      readOnly = true;
    };

    certPath = mkOption {
      type = types.str;
      default = "/var/lib/acme/${cfg.domain}/fullchain.pem";
      description = "Path to the full certificate chain";
      readOnly = true;
    };

    keyPath = mkOption {
      type = types.str;
      default = "/var/lib/acme/${cfg.domain}/key.pem";
      description = "Path to the private key";
      readOnly = true;
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable (mkMerge [
    # --------------------------------------------------------------------------
    # CORE ACME CONFIGURATION
    # --------------------------------------------------------------------------
    {
      security.acme = {
        acceptTerms = true;

        defaults = {
          email = cfg.email;
          server = mkIf cfg.staging "https://acme-staging-v02.api.letsencrypt.org/directory";
        };

        certs.${cfg.domain} = {
          domain = "*.${cfg.domain}";
          extraDomainNames = cfg.extraDomains;
          dnsProvider = cfg.dnsProvider;
          environmentFile = cfg.credentialsFile;
          dnsPropagationCheck = cfg.dnsPropagationCheck;
          group = "nginx";
        };
      };

      # Ensure nginx can read certificates
      users.users.nginx = {
        isSystemUser = true;
        group = "nginx";
        extraGroups = ["acme"];
      };

      users.groups.nginx = {};
      users.groups.acme = {};
    }

    # --------------------------------------------------------------------------
    # RFC2136 BIND DNS SETUP (optional)
    # --------------------------------------------------------------------------
    (mkIf cfg.enableRfc2136 {
      services.bind = {
        enable = true;
        extraConfig = ''
          include "/var/lib/secrets/dnskeys.conf";
        '';
        zones = [
          rec {
            name = cfg.rfc2136Zone;
            file = "/var/db/bind/${name}";
            master = true;
            extraConfig = "allow-update { key rfc2136key.${cfg.rfc2136Zone}.; };";
          }
        ];
      };

      # TSIG key generation for RFC2136
      systemd.services.dns-rfc2136-conf = {
        requiredBy = [
          "acme-${cfg.domain}.service"
          "bind.service"
        ];
        before = [
          "acme-${cfg.domain}.service"
          "bind.service"
        ];
        unitConfig = {
          ConditionPathExists = "!/var/lib/secrets/dnskeys.conf";
        };
        serviceConfig = {
          Type = "oneshot";
          UMask = 77;
        };
        path = [pkgs.bind];
        script = ''
          mkdir -p /var/lib/secrets
          chmod 755 /var/lib/secrets
          tsig-keygen rfc2136key.${cfg.rfc2136Zone} > /var/lib/secrets/dnskeys.conf
          chown named:root /var/lib/secrets/dnskeys.conf
          chmod 400 /var/lib/secrets/dnskeys.conf

          # Extract secret value from dnskeys.conf for ACME
          while read x y; do
            if [ "$x" = "secret" ]; then
              secret="''${y:1:''${#y}-3}"
            fi
          done < /var/lib/secrets/dnskeys.conf

          cat > /var/lib/secrets/certs.secret << EOF
          RFC2136_NAMESERVER='127.0.0.1:53'
          RFC2136_TSIG_ALGORITHM='hmac-sha256.'
          RFC2136_TSIG_KEY='rfc2136key.${cfg.rfc2136Zone}'
          RFC2136_TSIG_SECRET='$secret'
          EOF
          chmod 400 /var/lib/secrets/certs.secret
        '';
      };
    })

    # --------------------------------------------------------------------------
    # NGINX DEPENDENCIES
    # --------------------------------------------------------------------------
    {
      # Ensure nginx waits for certificates
      systemd.services.nginx = {
        wants = ["acme-finished-${cfg.domain}.target"];
        after = ["acme-finished-${cfg.domain}.target"];
      };
    }
  ]);
}

