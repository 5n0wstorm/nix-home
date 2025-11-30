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

    theme = mkOption {
      type = types.enum ["light" "dark" "grey" "auto"];
      default = "light";
      description = "UI theme for Authelia portal";
    };

    defaultRedirectionUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default URL to redirect to after authentication if no referer";
      example = "https://home.example.com/";
    };

    defaultPolicy = mkOption {
      type = types.enum ["bypass" "one_factor" "two_factor" "deny"];
      default = "one_factor";
      description = ''
        Default access policy for all domains.
        - bypass: No authentication required
        - one_factor: Username/password required
        - two_factor: Username/password + TOTP/WebAuthn required
        - deny: Deny all access
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
        "^/api/.*"
        "^/\\.well-known/.*"
      ];
      description = ''
        List of path regex patterns to bypass authentication on all domains.
        Uses regex syntax (not glob). Useful for API endpoints and discovery paths.
      '';
      example = ["^/api/.*" "^/public/.*"];
    };

    twoFactorDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of domains requiring two-factor authentication.
        These override the default policy.
      '';
    };

    apiBypassDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of domains where /api/* paths should bypass authentication.
        Useful for *arr apps and similar services with API access.
      '';
      example = ["sonarr.example.com" "radarr.example.com"];
    };

    # Regulation (brute force protection)
    regulation = {
      maxRetries = mkOption {
        type = types.int;
        default = 3;
        description = "Number of failed login attempts before user is banned";
      };

      findTime = mkOption {
        type = types.str;
        default = "2m";
        description = "Time window for counting failed attempts";
      };

      banTime = mkOption {
        type = types.str;
        default = "5m";
        description = "Duration of ban after max retries exceeded";
      };
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

    # Database storage configuration
    database = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Use MySQL/MariaDB database instead of SQLite";
      };

      # Direct value options (for simple configs)
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Database server hostname (ignored if hostFile is set)";
      };

      port = mkOption {
        type = types.port;
        default = 3306;
        description = "Database server port";
      };

      database = mkOption {
        type = types.str;
        default = "authelia";
        description = "Database name (ignored if databaseFile is set)";
      };

      username = mkOption {
        type = types.str;
        default = "authelia";
        description = "Database username (ignored if usernameFile is set)";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing database password";
      };

      # File-based options (for secrets management)
      hostFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing database hostname";
      };

      databaseFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing database name";
      };

      usernameFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing database username";
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

    rememberMeDuration = mkOption {
      type = types.str;
      default = "1M";
      description = "Duration for 'remember me' sessions (use -1 to disable)";
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

      identifier = mkOption {
        type = types.str;
        default = "";
        description = "HELO/EHLO identifier for SMTP";
        example = "galadriel.sn0wstorm.com";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing SMTP password";
      };

      tls = {
        serverName = mkOption {
          type = types.str;
          default = "";
          description = "TLS server name for certificate validation";
        };

        skipVerify = mkOption {
          type = types.bool;
          default = false;
          description = "Skip TLS certificate verification (not recommended)";
        };

        minimumVersion = mkOption {
          type = types.str;
          default = "TLS1.2";
          description = "Minimum TLS version";
        };
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
        theme = cfg.theme;
        default_2fa_method = "totp";
        default_redirection_url = mkIf (cfg.defaultRedirectionUrl != null) cfg.defaultRedirectionUrl;

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
          timeout = "60s";
          selection_criteria = {
            attestation_conveyance_preference = "indirect";
            user_verification = "preferred";
          };
        };

        # NTP configuration
        ntp = {
          address = "time.cloudflare.com:123";
          version = 4;
          max_desync = "3s";
          disable_startup_check = true;
        };

        # Regulation (brute force protection)
        regulation = {
          max_retries = cfg.regulation.maxRetries;
          find_time = cfg.regulation.findTime;
          ban_time = cfg.regulation.banTime;
        };

        # Session configuration
        session = {
          name = "authelia_session";
          cookies = [
            {
              domain = cfg.sessionDomain;
              authelia_url = "https://${cfg.domain}";
              same_site = "lax";
            }
          ];
          expiration = cfg.sessionExpiration;
          inactivity = cfg.sessionInactivity;
          remember_me = cfg.rememberMeDuration;
        };

        # Storage configuration
        # For file-based secrets, we use Authelia's env var support:
        # AUTHELIA__STORAGE__MYSQL__HOST, AUTHELIA__STORAGE__MYSQL__DATABASE, etc.
        storage =
          if cfg.database.enable
          then {
            mysql = {
              # These get overridden by environment variables when file-based secrets are used
              host = cfg.database.host;
              port = cfg.database.port;
              database = cfg.database.database;
              username = cfg.database.username;
            };
          }
          else {
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
              })
              cfg.bypassDomains)
            ++
            # API bypass for specific domains (e.g., *arr apps)
            (map (domain: {
                domain = domain;
                resources = ["^/api/.*$"];
                policy = "bypass";
              })
              cfg.apiBypassDomains)
            ++
            # Bypass rules for specific paths on all domains
            (map (path: {
                domain = "*.${acmeCfg.domain}";
                resources = [path];
                policy = "bypass";
              })
              cfg.bypassPaths)
            ++
            # Two-factor rules for high-security domains
            (map (domain: {
                domain = domain;
                policy = "two_factor";
              })
              cfg.twoFactorDomains)
            ++
            # Catch-all rule for wildcard domain with default one_factor
            # (ensures *.domain.com gets one_factor even if default is deny)
            [
              {
                domain = "*.${acmeCfg.domain}";
                policy = "one_factor";
              }
            ]
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
            disable_startup_check = true;
            smtp =
              {
                address = "submission://${cfg.smtp.host}:${toString cfg.smtp.port}";
                username = cfg.smtp.username;
                sender = cfg.smtp.sender;
                subject = "[Authelia] {title}";
                startup_check_address = "test@authelia.com";
              }
              // (
                if cfg.smtp.identifier != ""
                then {identifier = cfg.smtp.identifier;}
                else {}
              )
              // {
                tls = {
                  skip_verify = cfg.smtp.tls.skipVerify;
                  minimum_version = cfg.smtp.tls.minimumVersion;
                }
                // (
                  if cfg.smtp.tls.serverName != ""
                  then {server_name = cfg.smtp.tls.serverName;}
                  else {}
                );
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

    # Create environment file with secrets from files
    # Authelia supports AUTHELIA__* environment variables to override config
    systemd.services."authelia-main-secrets" = mkIf cfg.database.enable {
      description = "Prepare Authelia secrets environment file";
      before = ["authelia-main.service"];
      requiredBy = ["authelia-main.service"];
      after = ["sops-nix.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Run as root to create directory, then chown
      };
      script = let
        envFile = "/run/authelia-main/secrets.env";
      in ''
        mkdir -p /run/authelia-main
        chown authelia-main:authelia-main /run/authelia-main
        chmod 700 /run/authelia-main

        rm -f ${envFile}
        touch ${envFile}
        chmod 600 ${envFile}
        chown authelia-main:authelia-main ${envFile}

        ${optionalString (cfg.database.hostFile != null) ''
          if [ -f "${cfg.database.hostFile}" ]; then
            echo "AUTHELIA__STORAGE__MYSQL__HOST=$(cat ${cfg.database.hostFile})" >> ${envFile}
          else
            echo "Warning: ${cfg.database.hostFile} not found"
          fi
        ''}
        ${optionalString (cfg.database.databaseFile != null) ''
          if [ -f "${cfg.database.databaseFile}" ]; then
            echo "AUTHELIA__STORAGE__MYSQL__DATABASE=$(cat ${cfg.database.databaseFile})" >> ${envFile}
          else
            echo "Warning: ${cfg.database.databaseFile} not found"
          fi
        ''}
        ${optionalString (cfg.database.usernameFile != null) ''
          if [ -f "${cfg.database.usernameFile}" ]; then
            echo "AUTHELIA__STORAGE__MYSQL__USERNAME=$(cat ${cfg.database.usernameFile})" >> ${envFile}
          else
            echo "Warning: ${cfg.database.usernameFile} not found"
          fi
        ''}
        ${optionalString (cfg.database.passwordFile != null) ''
          if [ -f "${cfg.database.passwordFile}" ]; then
            echo "AUTHELIA__STORAGE__MYSQL__PASSWORD=$(cat ${cfg.database.passwordFile})" >> ${envFile}
          else
            echo "Warning: ${cfg.database.passwordFile} not found"
          fi
        ''}
        ${optionalString (cfg.smtp.enable && cfg.smtp.passwordFile != null) ''
          if [ -f "${cfg.smtp.passwordFile}" ]; then
            echo "AUTHELIA__NOTIFIER__SMTP__PASSWORD=$(cat ${cfg.smtp.passwordFile})" >> ${envFile}
          else
            echo "Warning: ${cfg.smtp.passwordFile} not found"
          fi
        ''}

        echo "Authelia secrets environment file created"
      '';
    };

    systemd.services."authelia-main" = mkIf cfg.database.enable {
      serviceConfig.EnvironmentFile = "/run/authelia-main/secrets.env";
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
