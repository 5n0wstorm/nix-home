{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.mysql;
in {
  # ============================================================================
  # MYSQL/MARIADB DATABASE SERVER MODULE
  #
  # This module provides a centralized MySQL/MariaDB server that can serve
  # multiple applications. It supports both manual database configuration and
  # automatic database provisioning through service requests.
  #
  # USAGE:
  #
  # 1. Enable the module:
  #    fleet.apps.mysql.enable = true;
  #
  # 2. Request databases for your services (recommended):
  #    fleet.apps.mysql.databaseRequests = {
  #      myservice = {
  #        database = "myservice_db";
  #        passwordFile = "/run/secrets/myservice_db_password";
  #      };
  #    };
  #
  # 3. Access connection info:
  #    # In your service module:
  #    myServiceConfig = config.fleet.apps.mysql.connections.myservice;
  #    # This gives you: host, port, database, user, passwordFile
  #
  # 4. Manual database configuration (advanced):
  #    fleet.apps.mysql.databases = {
  #      mydb = {
  #        name = "mydb";
  #        users = {
  #          myuser = {
  #            passwordFile = "/run/secrets/myuser_password";
  #          };
  #        };
  #      };
  #    };
  # ============================================================================
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.mysql = {
    enable = mkEnableOption "MySQL/MariaDB database server";

    package = mkOption {
      type = types.package;
      default = pkgs.mariadb;
      description = "MySQL/MariaDB package to use";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/mysql";
      description = "Data directory for MySQL/MariaDB";
    };

    port = mkOption {
      type = types.port;
      default = 3306;
      description = "Port for MySQL/MariaDB to listen on";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to bind MySQL/MariaDB to";
    };

    # Database requests from other services
    databaseRequests = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          database = mkOption {
            type = types.str;
            description = "Database name requested by service";
          };

          user = mkOption {
            type = types.str;
            default = "";
            description = "Database user name (defaults to service name if empty)";
          };

          passwordFile = mkOption {
            type = types.path;
            description = "Path to file containing user password";
          };

          permissions = mkOption {
            type = types.str;
            default = "ALL PRIVILEGES";
            description = "SQL permissions to grant to user";
          };

          host = mkOption {
            type = types.str;
            default = "localhost";
            description = "Host from which user can connect";
          };

          schema = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to SQL schema file to initialize database";
          };
        };
      });
      default = {};
      description = "Database requests from other services";
      example = {
        authelia = {
          database = "authelia";
          passwordFile = "/run/secrets/authelia_db_password";
        };
      };
    };

    # Manual database and user management (for complex setups)
    databases = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Database name";
          };

          schema = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to SQL schema file to initialize database";
          };

          users = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                passwordFile = mkOption {
                  type = types.path;
                  description = "Path to file containing user password";
                };

                permissions = mkOption {
                  type = types.str;
                  default = "ALL PRIVILEGES";
                  description = "SQL permissions to grant to user";
                };

                host = mkOption {
                  type = types.str;
                  default = "localhost";
                  description = "Host from which user can connect";
                };
              };
            });
            default = {};
            description = "Users for this database";
          };
        };
      });
      default = {};
      description = "Database configurations with associated users";
      example = {
        authelia = {
          name = "authelia";
          users = {
            authelia = {
              passwordFile = "/run/secrets/authelia_db_password";
            };
          };
        };
      };
    };

    # MySQL/MariaDB configuration
    settings = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = {
        mysqld = {
          bind-address = cfg.bindAddress;
          port = cfg.port;
          innodb_buffer_pool_size = "128M";
          innodb_log_file_size = "32M";
          max_connections = 100;
          skip_name_resolve = true;
        };
      };
      description = "MySQL/MariaDB configuration options";
    };

    # Connection information (read-only, computed from configuration)
    connections = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          host = mkOption {
            type = types.str;
            default = cfg.bindAddress;
            description = "Database host";
          };

          port = mkOption {
            type = types.port;
            default = cfg.port;
            description = "Database port";
          };

          database = mkOption {
            type = types.str;
            description = "Database name";
          };

          user = mkOption {
            type = types.str;
            description = "Database user";
          };

          passwordFile = mkOption {
            type = types.path;
            description = "Password file path";
          };
        };
      });
      readOnly = true;
      description = "Computed database connection information for services";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # ----------------------------------------------------------------------------
    # COMPUTED CONNECTIONS
    # ----------------------------------------------------------------------------

    fleet.apps.mysql.connections = let
      # Combine databaseRequests with explicit databases
      fromRequests = mapAttrs' (serviceName: req:
        nameValuePair serviceName {
          host = cfg.bindAddress;
          port = cfg.port;
          database = req.database;
          user =
            if req.user != ""
            then req.user
            else serviceName;
          passwordFile = req.passwordFile;
        })
      cfg.databaseRequests;

      fromDatabases = flatten (
        mapAttrsToList (dbName: dbCfg: [
          mapAttrs'
          (userName: userCfg:
            nameValuePair "${dbName}-${userName}" {
              host = cfg.bindAddress;
              port = cfg.port;
              database = dbCfg.name;
              user = userName;
              passwordFile = userCfg.passwordFile;
            })
          dbCfg.users
        ])
        cfg.databases
      );

      allConnections = fromRequests // (listToAttrs fromDatabases);
    in
      allConnections;
    # ----------------------------------------------------------------------------
    # ASSERTIONS
    # ----------------------------------------------------------------------------

    assertions = [
      {
        assertion = cfg.bindAddress != "0.0.0.0";
        message = ''
          fleet.apps.mysql.bindAddress should not be set to "0.0.0.0" for security reasons.
          Consider using "127.0.0.1" for local access only.
        '';
      }
    ];

    # ----------------------------------------------------------------------------
    # MYSQL SERVICE CONFIGURATION
    # ----------------------------------------------------------------------------

    services.mysql = {
      enable = true;
      package = cfg.package;
      dataDir = cfg.dataDir;

      inherit (cfg) settings;
    };

    # The upstream NixOS mysql unit runs an ExecStartPost hook ("mysql-post-start")
    # which can fail hard (and thus stop the service) if local maintenance auth
    # doesn't match the existing datadir state. We do our own provisioning via the
    # mysql-user-setup oneshot below, so keep mysql.service itself healthy.
    systemd.services.mysql.postStart = mkForce "";

    # ----------------------------------------------------------------------------
    # DATABASE USER SETUP SERVICE
    # ----------------------------------------------------------------------------
    # Creates database users after MySQL starts, reading passwords from secret files

    systemd.services.mysql-user-setup = {
      description = "Setup MySQL database users";
      after = ["mysql.service"];
      requires = ["mysql.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      path = [cfg.package];
      script = let
        # Combine databaseRequests with explicit databases
        fromRequests = mapAttrs' (serviceName: req:
          nameValuePair req.database {
            name = req.database;
            users = {
              ${
                if req.user != ""
                then req.user
                else serviceName
              } = {
                inherit (req) passwordFile permissions host;
              };
            };
            inherit (req) schema;
          })
        cfg.databaseRequests;

        allDatabases = fromRequests // cfg.databases;

        dbCommands = concatStringsSep "\n" (
          mapAttrsToList (
            _dbName: dbCfg: let
              schemaBlock = optionalString (dbCfg.schema != null) (concatStringsSep "\n" [
                "if [ -f \"${dbCfg.schema}\" ]; then"
                "  echo \"Applying schema for database ${dbCfg.name} from ${dbCfg.schema}\""
                "  mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -u root \"${dbCfg.name}\" < \"${dbCfg.schema}\""
                "else"
                "  echo \"Warning: Schema file ${dbCfg.schema} not found for database ${dbCfg.name}\""
                "fi"
              ]);
            in
              concatStringsSep "\n" ([
                  "# Ensure database exists: ${dbCfg.name}"
                  "mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -u root <<EOF"
                  "CREATE DATABASE IF NOT EXISTS \\`${dbCfg.name}\\`;"
                  "EOF"
                ]
                ++ optionals (dbCfg.schema != null) [schemaBlock])
          )
          allDatabases
        );

        userCommands = concatStringsSep "\n" (
          flatten (
            mapAttrsToList (
              _dbName: dbCfg:
                mapAttrsToList (
                  userName: userCfg:
                    concatStringsSep "\n" [
                      "# Setup user: ${userName} for database: ${dbCfg.name}"
                      "if [ -f \"${userCfg.passwordFile}\" ]; then"
                      "  PASSWORD=$(cat \"${userCfg.passwordFile}\")"
                      "  mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -u root <<EOF"
                      "CREATE USER IF NOT EXISTS '${userName}'@'${userCfg.host}' IDENTIFIED BY '$PASSWORD';"
                      "ALTER USER '${userName}'@'${userCfg.host}' IDENTIFIED BY '$PASSWORD';"
                      "GRANT ${userCfg.permissions} ON \\`${dbCfg.name}\\`.* TO '${userName}'@'${userCfg.host}';"
                      "FLUSH PRIVILEGES;"
                      "EOF"
                      "  echo \"User ${userName}@${userCfg.host} configured for ${dbCfg.name}\""
                      "else"
                      "  echo \"Warning: Password file ${userCfg.passwordFile} not found for ${userName}\""
                      "fi"
                    ]
                )
                dbCfg.users
            )
            allDatabases
          )
        );
      in ''
        # Wait for MySQL to be ready
        for i in {1..30}; do
          if mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -u root -e "SELECT 1" &>/dev/null; then
            break
          fi
          echo "Waiting for MySQL to be ready..."
          sleep 1
        done

        ${dbCommands}

        ${userCommands}

        echo "MySQL user setup complete"
      '';
    };

    # ----------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # ----------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf (cfg.bindAddress != "127.0.0.1") [cfg.port];

    # Add MariaDB client tools for database management
    environment.systemPackages = [cfg.package];
  };
}
