{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.postgresql;
in {
  # ============================================================================
  # POSTGRESQL DATABASE SERVER MODULE
  #
  # This module provides a centralized PostgreSQL server that can serve
  # multiple applications. Each database entry automatically creates a role
  # (user) and database with the same name.
  #
  # USAGE:
  #
  # 1. Enable the module:
  #    fleet.apps.postgresql.enable = true;
  #
  # 2. Configure databases (each creates role + DB with same name):
  #    fleet.apps.postgresql.databases = {
  #      myapp = {
  #        dbName = "myapp";  # Optional, defaults to key name
  #        secretPrefix = "postgresql/myapp";  # Optional, defaults to postgresql/<key>
  #      };
  #    };
  #
  # 3. Add secrets to secrets.yaml:
  #    postgresql:
  #      myapp:
  #        username: myapp_user
  #        password: <encrypted>
  #
  # 4. Declare sops secrets in host config:
  #    sops.secrets."postgresql/myapp/username" = {
  #      owner = "postgres"; group = "postgres"; mode = "0400";
  #    };
  #    sops.secrets."postgresql/myapp/password" = {
  #      owner = "postgres"; group = "postgres"; mode = "0400";
  #    };
  # ============================================================================

  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.postgresql = {
    enable = mkEnableOption "PostgreSQL database server";

    package = mkOption {
      type = types.package;
      default = pkgs.postgresql_16;
      description = "PostgreSQL package to use";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/postgresql/${cfg.package.psqlSchema}";
      description = "Data directory for PostgreSQL";
    };

    port = mkOption {
      type = types.port;
      default = 5432;
      description = "Port for PostgreSQL to listen on";
    };

    # Database configurations - each creates a role and database
    databases = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          dbName = mkOption {
            type = types.str;
            description = "Database name (defaults to attribute name if not specified)";
          };

          secretPrefix = mkOption {
            type = types.str;
            description = "Prefix path for secrets (username at {prefix}/username, password at {prefix}/password)";
          };
        };
      });
      default = {};
      description = "Database configurations with associated users";
      example = {
        myapp = {
          dbName = "myapp";
          secretPrefix = "postgresql/myapp";
        };
      };
    };

    # PostgreSQL configuration settings
    settings = mkOption {
      type = types.attrsOf types.anything;
      default = {
        listen_addresses = "127.0.0.1";
        port = cfg.port;
        max_connections = 100;
        shared_buffers = "128MB";
      };
      description = "PostgreSQL configuration settings";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # POSTGRESQL SERVICE CONFIGURATION
    # --------------------------------------------------------------------------

    services.postgresql = {
      enable = true;
      package = cfg.package;
      dataDir = cfg.dataDir;
      settings = cfg.settings;

      # Enable peer authentication for local postgres user
      authentication = mkOverride 10 ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             postgres                                peer
        local   all             all                                     peer
        host    all             all             127.0.0.1/32            scram-sha-256
        host    all             all             ::1/128                 scram-sha-256
      '';
    };

    # --------------------------------------------------------------------------
    # DATABASE AND USER PROVISIONING SERVICE
    # --------------------------------------------------------------------------
    # Creates roles and databases after PostgreSQL starts, reading credentials
    # from secret files rendered by sops-nix

    systemd.services.postgresql-provision = let
      # Build the provisioning script for each database entry
      provisionCommands = concatStringsSep "\n\n" (
        mapAttrsToList (
          key: dbCfg: let
            usernameFile = "/run/secrets/${dbCfg.secretPrefix}/username";
            passwordFile = "/run/secrets/${dbCfg.secretPrefix}/password";
            dbName = dbCfg.dbName;
          in ''
            echo "=== Provisioning database: ${dbName} (${key}) ==="

            # Check if secret files exist
            if [ ! -f "${usernameFile}" ]; then
              echo "ERROR: Username file not found: ${usernameFile}"
              exit 1
            fi

            if [ ! -f "${passwordFile}" ]; then
              echo "ERROR: Password file not found: ${passwordFile}"
              exit 1
            fi

            # Read credentials from secret files
            USERNAME=$(cat "${usernameFile}")
            PASSWORD=$(cat "${passwordFile}")

            # Optional sanity checks (avoid quoting edge-cases)
            if ! echo "$USERNAME" | grep -Eq '^[A-Za-z0-9_]+$'; then
              echo "ERROR: Username contains unsupported characters: $USERNAME"
              exit 1
            fi

            # Escape single quotes in password for SQL (replace ' with '')
            PASSWORD_ESCAPED=$(printf %s "$PASSWORD" | sed "s/'/''/g")

            echo "  Username: $USERNAME"
            echo "  Database: ${dbName}"

            # Check if role exists
            if psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$USERNAME'" | grep -q 1; then
              echo "  Role $USERNAME exists, updating password..."
              psql -v ON_ERROR_STOP=1 <<EOF
            ALTER ROLE "$USERNAME" WITH LOGIN PASSWORD '$PASSWORD_ESCAPED';
            EOF
            else
              echo "  Creating role $USERNAME..."
              psql -v ON_ERROR_STOP=1 <<EOF
            CREATE ROLE "$USERNAME" WITH LOGIN PASSWORD '$PASSWORD_ESCAPED';
            EOF
            fi

            # Check if database exists
            if psql -tAc "SELECT 1 FROM pg_database WHERE datname='${dbName}'" | grep -q 1; then
              echo "  Database ${dbName} exists, updating owner..."
              psql -v ON_ERROR_STOP=1 <<EOF
            ALTER DATABASE "${dbName}" OWNER TO "$USERNAME";
            EOF
            else
              echo "  Creating database ${dbName}..."
              psql -v ON_ERROR_STOP=1 <<EOF
            CREATE DATABASE "${dbName}" OWNER "$USERNAME";
            EOF
            fi

            # Grant all privileges
            psql -v ON_ERROR_STOP=1 <<EOF
            GRANT ALL PRIVILEGES ON DATABASE "${dbName}" TO "$USERNAME";
            EOF

            echo "  ✓ Database ${dbName} provisioned successfully"
          ''
        )
        cfg.databases
      );
    in {
      description = "Provision PostgreSQL databases and users from secrets";
      after = ["postgresql.service"];
      requires = ["postgresql.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
        Group = "postgres";
      };

      path = [cfg.package];

      script = ''
        set -e

        echo "Starting PostgreSQL database provisioning..."

        # Wait for PostgreSQL to be ready
        for i in {1..30}; do
          if psql -c "SELECT 1" &>/dev/null; then
            echo "PostgreSQL is ready"
            break
          fi
          echo "Waiting for PostgreSQL to be ready... ($i/30)"
          sleep 1
        done

        # Provision each database
        ${provisionCommands}

        echo ""
        echo "PostgreSQL provisioning complete!"
        echo ""
        echo "=== Current roles ==="
        psql -c "\du"
        echo ""
        echo "=== Current databases ==="
        psql -c "\l"
      '';
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    # Only open firewall if not listening on localhost only
    networking.firewall.allowedTCPPorts = mkIf (cfg.settings.listen_addresses or "127.0.0.1" != "127.0.0.1") [cfg.port];

    # Add PostgreSQL client tools for database management
    environment.systemPackages = [cfg.package];
  };
}

