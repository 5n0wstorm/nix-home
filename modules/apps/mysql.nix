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

    # Homepage integration
    homepage = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Register this service with the homepage dashboard";
      };

      name = mkOption {
        type = types.str;
        default = "MySQL";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Database Server";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-mysql";
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
    # ----------------------------------------------------------------------------
    # COMPUTED CONNECTIONS
    # ----------------------------------------------------------------------------

    fleet.apps.mysql.connections = let
      # Combine databaseRequests with explicit databases
      fromRequests = mapAttrs' (serviceName: req: nameValuePair serviceName {
        host = cfg.bindAddress;
        port = cfg.port;
        database = req.database;
        user = if req.user != "" then req.user else serviceName;
        passwordFile = req.passwordFile;
      }) cfg.databaseRequests;

      fromDatabases = flatten (
        mapAttrsToList (dbName: dbCfg: [
          mapAttrs' (userName: userCfg: nameValuePair "${dbName}-${userName}" {
            host = cfg.bindAddress;
            port = cfg.port;
            database = dbCfg.name;
            user = userName;
            passwordFile = userCfg.passwordFile;
          }) dbCfg.users
        ]) cfg.databases
      );

      allConnections = fromRequests // (listToAttrs fromDatabases);
    in allConnections;
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
    # HOMEPAGE DASHBOARD REGISTRATION
    # ----------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.mysql = mkIf cfg.homepage.enable {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      # MySQL doesn't have a web interface, so no href
      category = cfg.homepage.category;
    };

    # ----------------------------------------------------------------------------
    # MYSQL SERVICE CONFIGURATION
    # ----------------------------------------------------------------------------

    services.mysql = {
      enable = true;
      package = cfg.package;
      dataDir = cfg.dataDir;

      # Combine databaseRequests with explicit databases
      initialDatabases = let
        # Convert databaseRequests to database format
        fromRequests = mapAttrs' (serviceName: req: nameValuePair req.database {
          name = req.database;
          schema = req.schema;
          users = {
            ${if req.user != "" then req.user else serviceName} = {
              inherit (req) passwordFile permissions host;
            };
          };
        }) cfg.databaseRequests;

        # Merge with explicit databases, giving precedence to explicit config
        allDatabases = fromRequests // cfg.databases;
      in mapAttrsToList (name: dbCfg: {
        inherit (dbCfg) name;
        inherit (dbCfg) schema;
      }) allDatabases;

      # Generate initial script for users
      initialScript = let
        # Combine databaseRequests with explicit databases
        fromRequests = mapAttrs' (serviceName: req: nameValuePair req.database {
          name = req.database;
          schema = req.schema;
          users = {
            ${if req.user != "" then req.user else serviceName} = {
              inherit (req) passwordFile permissions host;
            };
          };
        }) cfg.databaseRequests;

        allDatabases = fromRequests // cfg.databases;
      in concatStringsSep "\n" (
        flatten (
          mapAttrsToList (dbName: dbCfg: [
            "# Database: ${dbName}"
          ] ++ (
            mapAttrsToList (userName: userCfg: [
              "CREATE USER IF NOT EXISTS '${userName}'@'${userCfg.host}' IDENTIFIED BY LOAD_FILE('${userCfg.passwordFile}');"
              "GRANT ${userCfg.permissions} ON ${dbCfg.name}.* TO '${userName}'@'${userCfg.host}';"
            ]) dbCfg.users
          ) ++ [
            "FLUSH PRIVILEGES;"
            ""
          ])
          allDatabases
        )
      );

      inherit (cfg) settings;
    };

    # ----------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # ----------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf (cfg.bindAddress != "127.0.0.1") [cfg.port];
  };
}
