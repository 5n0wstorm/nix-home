{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================
  #
  # DEPRECATED: This module is for development/testing only.
  # For production, use fleet.security.acme for Let's Encrypt certificates.
  #
  # This module provides self-signed certificate generation using minica,
  # which supports both regular domains and wildcard certificates.
  # Useful for local development when ACME DNS validation is not available.
  #
  # Example usage:
  #   fleet.security.selfSignedCA = {
  #     enable = true;
  #     wildcardDomains = ["*.local"];
  #   };
  #

  options.fleet.security.selfSignedCA = {
    enable = mkEnableOption "Self-signed Certificate Authority (development only)";

    caName = mkOption {
      type = types.str;
      default = "Fleet Development CA";
      description = "Name of the Certificate Authority";
    };

    domain = mkOption {
      type = types.str;
      default = "local";
      description = "Base domain for the wildcard certificate";
      example = "dev.local";
    };

    validityDays = mkOption {
      type = types.int;
      default = 365;
      description = "Certificate validity in days";
    };

    # Derived paths for nginx consumption (matching ACME module interface)
    certDir = mkOption {
      type = types.str;
      default = "/var/lib/fleet-ca";
      description = "Directory containing the certificate files";
      readOnly = true;
    };

    certPath = mkOption {
      type = types.str;
      default = "/var/lib/fleet-ca/_.${config.fleet.security.selfSignedCA.domain}/cert.pem";
      description = "Path to the certificate";
      readOnly = true;
    };

    keyPath = mkOption {
      type = types.str;
      default = "/var/lib/fleet-ca/_.${config.fleet.security.selfSignedCA.domain}/key.pem";
      description = "Path to the private key";
      readOnly = true;
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = let
    cfg = config.fleet.security.selfSignedCA;
  in
    mkIf cfg.enable {
      # --------------------------------------------------------------------------
      # DEPRECATION WARNING
      # --------------------------------------------------------------------------

      warnings = [
        ''
          fleet.security.selfSignedCA is deprecated for production use.
          Consider using fleet.security.acme for Let's Encrypt certificates.
          Self-signed certificates should only be used for local development.
        ''
      ];

      # --------------------------------------------------------------------------
      # CA AND CERTIFICATE GENERATION
      # --------------------------------------------------------------------------

      systemd.services.fleet-ca-setup = {
        description = "Setup Fleet Development Certificate Authority";
        wantedBy = ["multi-user.target"];
        before = ["nginx.service"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };

        script = ''
          set -euo pipefail

          CA_DIR="${cfg.certDir}"
          DOMAIN="*.${cfg.domain}"

          mkdir -p "$CA_DIR"
          cd "$CA_DIR"

          # Generate CA and wildcard certificate if not already done
          if [[ ! -f "minica.pem" ]]; then
            echo "Generating development CA and wildcard certificate..."

            ${pkgs.minica}/bin/minica \
              --ca-cert=minica.pem \
              --ca-key=minica-key.pem \
              --domains="$DOMAIN" \
              --validity-days=${toString cfg.validityDays}

            # Set proper permissions
            chmod 600 minica-key.pem
            chmod 644 minica.pem
            find . -name "*.pem" -type f -exec chmod 644 {} \;
            find . -name "*-key.pem" -type f -exec chmod 600 {} \;
          fi

          # Create symlinks for easy access
          ln -sf minica.pem ca-cert.pem
          ln -sf minica-key.pem ca-key.pem

          # Set ownership for nginx
          chown -R nginx:nginx "$CA_DIR"

          echo "Fleet Development CA setup complete!"
          echo "CA certificate: $CA_DIR/ca-cert.pem"
          echo "Wildcard cert:  $CA_DIR/_.${cfg.domain}/cert.pem"
          echo ""
          echo "To trust this CA, add ca-cert.pem to your browser/system trust store."
        '';
      };

      # --------------------------------------------------------------------------
      # USERS AND GROUPS
      # --------------------------------------------------------------------------

      users.users.nginx = {
        isSystemUser = true;
        group = "nginx";
      };

      users.groups.nginx = {};
    };
}
