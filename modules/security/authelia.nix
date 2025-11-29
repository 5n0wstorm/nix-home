{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.security.authelia;
  acmeCfg = config.fleet.security.acme;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================
  #
  # Authelia provides single sign-on (SSO) and multi-factor authentication (MFA)
  # for web applications behind the reverse proxy.
  #
  # By default, ALL domains are protected and require authentication.
  # Services can opt-out using the bypassDomains option or per-service
  # "fleet.authelia.bypass" label.
  #

  options.fleet.security.authelia = {
    enable = mkEnableOption "Authelia authentication portal";

    domain = mkOption {
      type = types.str;
      default = "auth.${acmeCfg.domain}";
      description = "Domain name for Authelia authentication portal";
    };

    port = mkOption {
      type = types.port;
      default = 9091;
      description = "Port for Authelia service";
    };

    defaultPolicy = mkOption {
      type = types.enum ["bypass" "one_factor" "two_factor"];
      default = "one_factor";
      description = ''
        Default access policy for all domains.
        - bypass: No authentication required
        - one_factor: Username/password required
        - two_factor: Username/password + TOTP/WebAuthn required
      '';
    };

    bypassDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of domains to bypass authentication.
        Use this for services that handle their own authentication (e.g., Vaultwarden).
      '';
      example = ["bitwarden.example.com" "public.example.com"];
    };

    bypassPaths = mkOption {
      type = types.listOf types.str;
      default = [
        "/api/**"
        "/.well-known/**"
      ];
      description = ''
        List of paths to bypass authentication on all domains.
        Useful for API endpoints and discovery paths.
      '';
    };

    twoFactorDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of domains requiring two-factor authentication.
        These override the default policy.
      '';
    };

    # Secrets configuration
    secrets = {
      jwtSecretFile = mkOption {
        type = types.path;
        description = "Path to file containing JWT secret (min 64 characters)";
        example = "/run/secrets/authelia/jwt_secret";
      };

      storageEncryptionKeyFile = mkOption {
        type = types.path;
        description = "Path to file containing storage encryption key (min 64 characters)";
        example = "/run/secrets/authelia/storage_encryption_key";
      };

      sessionSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing session secret (required for Redis)";
      };
    };

    # LDAP Configuration (optional)
    ldap = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Use LDAP for authentication backend";
      };

      url = mkOption {
        type = types.str;
        default = "ldap://localhost:3890";
        description = "LDAP server URL";
      };

      baseDN = mkOption {
        type = types.str;
        default = "dc=example,dc=com";
        description = "LDAP base DN for searches";
      };

      userFilter = mkOption {
        type = types.str;
        default = "(&(|({username_attribute}={input})({mail_attribute}={input}))(objectClass=person))";
        description = "LDAP filter for user searches";
      };

      adminPasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing LDAP admin password";
      };
    };

    # File-based authentication (default)
    usersFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to Authelia users_database.yml file.
        Required if LDAP is not enabled.
        
        Example users file format:
        users:
          admin:
            displayname: "Admin User"
            password: "$argon2id$..." 
            email: admin@example.com
            groups:
              - admins
      '';
    };

    # Session settings
    sessionDomain = mkOption {
      type = types.str;
      default = acmeCfg.domain;
      description = "Cookie domain for sessions (should match your base domain)";
    };

    sessionExpiration = mkOption {
      type = types.str;
      default = "12h";
      description = "Session expiration time";
    };

    sessionInactivity = mkOption {
      type = types.str;
      default = "45m";
      description = "Session inactivity timeout";
    };

    # SMTP settings for notifications
    smtp = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SMTP notifications";
      };

      host = mkOption {
        type = types.str;
        default = "smtp.gmail.com";
        description = "SMTP server hostname";
      };

      port = mkOption {
        type = types.port;
        default = 587;
        description = "SMTP server port";
      };

      username = mkOption {
        type = types.str;
        default = "";
        description = "SMTP username";
      };

      sender = mkOption {
        type = types.str;
        default = "authelia@${acmeCfg.domain}";
        description = "SMTP sender address";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing SMTP password";
      };
    };

    # Homepage integration
    homepage = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Register this service with the homepage dashboard";
      };

      name = mkOption {
        type = types.str;
        default = "Authelia";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Authentication Portal";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-authelia";
        description = "Icon for homepage";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Infrastructure";
        description = "Category on the homepage dashboard";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # ASSERTIONS
    # --------------------------------------------------------------------------

    assertions = [
      {
        assertion = cfg.ldap.enable || cfg.usersFile != null;
        message = ''
          fleet.security.authelia requires either LDAP authentication or a users file.
          Set fleet.security.authelia.ldap.enable = true; or provide a usersFile.
        '';
      }
      {
        assertion = acmeCfg.enable;
        message = ''
          fleet.security.authelia requires fleet.security.acme to be enabled
          for TLS certificate generation.
        '';
      }
    ];

    # --------------------------------------------------------------------------
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.authelia = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION (Authelia portal itself)
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.authelia = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.authelia.bypass" = "true"; # Authelia itself must be accessible
      };
    };

    # --------------------------------------------------------------------------
    # AUTHELIA SERVICE
    # --------------------------------------------------------------------------

    services.authelia.instances.main = {
      enable = true;

      secrets = {
        jwtSecretFile = cfg.secrets.jwtSecretFile;
        storageEncryptionKeyFile = cfg.secrets.storageEncryptionKeyFile;
        sessionSecretFile = cfg.secrets.sessionSecretFile;
      };

      settings = {
        theme = "auto";
        default_2fa_method = "totp";

        server = {
          address = "tcp://127.0.0.1:${toString cfg.port}";
          endpoints = {
            authz = {
              forward-auth = {
                implementation = "ForwardAuth";
              };
            };
          };
        };

        log = {
          level = "info";
          format = "text";
        };

        # TOTP configuration
        totp = {
          issuer = acmeCfg.domain;
          period = 30;
          skew = 1;
        };

        # WebAuthn configuration
        webauthn = {
          display_name = "Fleet Auth";
          attestation_conveyance_preference = "indirect";
          user_verification = "preferred";
          timeout = "60s";
        };

        # Session configuration
        session = {
          name = "authelia_session";
          cookies = [
            {
              domain = cfg.sessionDomain;
              authelia_url = "https://${cfg.domain}";
            }
          ];
          expiration = cfg.sessionExpiration;
          inactivity = cfg.sessionInactivity;
        };

        # Storage (local SQLite)
        storage = {
          local = {
            path = "/var/lib/authelia-main/db.sqlite3";
          };
        };

        # Access control rules
        access_control = {
          default_policy = cfg.defaultPolicy;

          rules =
            # Bypass rules for specific domains
            (map (domain: {
              domain = domain;
              policy = "bypass";
            }) cfg.bypassDomains)
            ++
            # Bypass rules for specific paths on all domains
            (map (path: {
              domain = "*.${acmeCfg.domain}";
              resources = [path];
              policy = "bypass";
            }) cfg.bypassPaths)
            ++
            # Two-factor rules for high-security domains
            (map (domain: {
              domain = domain;
              policy = "two_factor";
            }) cfg.twoFactorDomains)
            ++
            # Always bypass the auth portal itself
            [
              {
                domain = cfg.domain;
                policy = "bypass";
              }
            ];
        };

        # Notification provider
        notifier =
          if cfg.smtp.enable
          then {
            smtp = {
              address = "submission://${cfg.smtp.host}:${toString cfg.smtp.port}";
              username = cfg.smtp.username;
              sender = cfg.smtp.sender;
            };
          }
          else {
            # Filesystem notifier for development/testing
            filesystem = {
              filename = "/var/lib/authelia-main/notification.txt";
            };
          };

        # Authentication backend
        authentication_backend =
          if cfg.ldap.enable
          then {
            ldap = {
              address = cfg.ldap.url;
              base_dn = cfg.ldap.baseDN;
              users_filter = cfg.ldap.userFilter;
              implementation = "custom";
              attributes = {
                username = "uid";
                display_name = "displayName";
                mail = "mail";
                group_name = "cn";
              };
            };
          }
          else {
            file = {
              path = cfg.usersFile;
            };
          };
      };
    };

    # SMTP password environment
    systemd.services."authelia-main" = mkIf cfg.smtp.enable {
      serviceConfig.EnvironmentFile = mkIf (cfg.smtp.passwordFile != null) cfg.smtp.passwordFile;
    };

    # --------------------------------------------------------------------------
    # DIRECTORY SETUP
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      "d /var/lib/authelia-main 0700 authelia-main authelia-main -"
    ];

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}

