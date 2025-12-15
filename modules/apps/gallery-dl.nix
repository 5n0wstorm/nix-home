{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.galleryDl;
  sharedMediaCfg =
    attrByPath ["fleet" "media" "shared"] {
      enable = false;
      group = "root";
    }
    config;
  archiveGroup =
    if (sharedMediaCfg.enable or false)
    then sharedMediaCfg.group
    else "root";
  archiveBase = removeSuffix "/" cfg.archiveDir;
  galleryDlBaseDir = "${archiveBase}/gallery-dl";

  enabledInstances = filterAttrs (_name: inst: inst.enable) cfg.instances;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.galleryDl = {
    enable = mkEnableOption "Custom gallery-dl from Gitea fork";

    archiveDir = mkOption {
      type = types.str;
      default = "/data/archive/";
      description = "Directory used to store gallery-dl archives/output";
      example = "/data/archive/";
    };

    user = mkOption {
      type = types.str;
      default = "gallery-dl";
      description = "User to run gallery-dl instances as";
    };

    group = mkOption {
      type = types.str;
      default = "gallery-dl";
      description = "Primary group to run gallery-dl instances as";
    };

    instances = mkOption {
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          enable = mkEnableOption "gallery-dl instance '${name}'";

          config = mkOption {
            type = types.nullOr types.attrs;
            default = null;
            description = ''
              Non-secret gallery-dl config as a Nix attrset. When set, it will be serialized to JSON
              and written to `<workingDir>/config.json` at runtime. Use placeholders like
              `@TG_API_ID@` and provide their values via `configSubstitutions` (from SOPS secrets).
            '';
          };

          configSubstitutions = mkOption {
            type = types.attrsOf (types.oneOf [types.path types.str]);
            default = {};
            description = ''
              Placeholder -> secret file path mappings for rendering `config`.
              Each placeholder string will be replaced with the file contents (trimmed).

              Example keys: "@TG_API_ID@", "@TG_API_HASH@", "@TG_SESSION_STRING@", "@PG_CONN@"
            '';
            example = {
              "@TG_API_ID@" = "/run/secrets/gallery-dl-telegram-api-id";
              "@TG_API_HASH@" = "/run/secrets/gallery-dl-telegram-api-hash";
              "@TG_SESSION_STRING@" = "/run/secrets/gallery-dl-telegram-session-string";
              "@PG_CONN@" = "/run/secrets/gallery-dl-postgres-conn";
            };
          };

          urlFile = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Path to a file containing URLs (one per line), passed via --input-file";
            example = "/data/archive/gallery-dl/telegram/urls.txt";
          };

          urls = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "URLs to download for this instance (passed as arguments to gallery-dl)";
            example = ["https://example.com/user/foo"];
          };

          args = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Extra CLI args passed to gallery-dl before URLs";
            example = ["--verbose" "--write-metadata"];
          };

          configFile = mkOption {
            type = types.nullOr (types.oneOf [types.path types.str]);
            default = null;
            description = "Optional gallery-dl config file (passed via --config)";
            example = "/etc/gallery-dl/config.json";
          };

          onCalendar = mkOption {
            type = types.str;
            default = "minutely";
            description = "systemd OnCalendar schedule (default: every minute)";
            example = "*-*-* *:*:00";
          };

          workingDir = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Working directory for this instance (defaults to a per-instance dir under archiveDir)";
            example = "/data/archive/gallery-dl/telegram";
          };

          downloadArchiveFile = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional --download-archive path (defaults to <workingDir>/archive.txt)";
            example = "/data/archive/gallery-dl/telegram/archive.txt";
          };
        };
      }));
      default = {};
      description = "Multiple gallery-dl instances, each with its own systemd service+timer";
      example = {
        telegram = {
          enable = true;
          onCalendar = "minutely";
          args = ["--verbose" "--write-metadata"];
          urls = ["https://example.com/user/foo"];
        };
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # USER / GROUP
    # --------------------------------------------------------------------------

    users.groups.${cfg.group} = {};

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
    };

    # --------------------------------------------------------------------------
    # DIRECTORY STRUCTURE
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules =
      [
        # Ensure /data/archive exists even if not provided by other modules.
        "d /data/archive 0775 root ${archiveGroup} -"

        # gallery-dl workspace (archives, downloads, metadata, etc.)
        "d ${archiveBase} 0775 root ${archiveGroup} -"
        "d ${galleryDlBaseDir} 0775 root ${archiveGroup} -"
      ]
      ++ (mapAttrsToList (name: inst: let
        instanceDir =
          if inst.workingDir != null
          then inst.workingDir
          else "${galleryDlBaseDir}/${name}";
      in "d ${instanceDir} 0775 ${cfg.user} ${archiveGroup} -")
      enabledInstances);

    # --------------------------------------------------------------------------
    # SERVICES + TIMERS (multi-instance)
    # --------------------------------------------------------------------------

    systemd.services = mapAttrs' (name: inst: let
      instanceDir =
        if inst.workingDir != null
        then inst.workingDir
        else "${galleryDlBaseDir}/${name}";
      renderedConfigFile = "${instanceDir}/config.json";
      effectiveConfigFile =
        if inst.config != null
        then renderedConfigFile
        else inst.configFile;
      archiveFile =
        if inst.downloadArchiveFile != null
        then inst.downloadArchiveFile
        else "${instanceDir}/archive.txt";
      args =
        (optional (effectiveConfigFile != null) "--config")
        ++ (optional (effectiveConfigFile != null) (toString effectiveConfigFile))
        ++ ["--download-archive" archiveFile]
        ++ (optional (inst.urlFile != null) "--input-file")
        ++ (optional (inst.urlFile != null) inst.urlFile)
        ++ inst.args
        ++ (optionals (inst.urlFile == null) inst.urls);
    in
      nameValuePair "gallery-dl-${name}" {
        description = "gallery-dl instance: ${name}";

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = cfg.group;
          SupplementaryGroups = optional (sharedMediaCfg.enable or false) archiveGroup;
          WorkingDirectory = instanceDir;
          Nice = 10;
        };

        script = let
          subsJson = builtins.toJSON (mapAttrs (_k: v: toString v) inst.configSubstitutions);
          configJson =
            if inst.config != null
            then builtins.toJSON inst.config
            else null;
        in ''
          set -euo pipefail

          ${optionalString (inst.config != null) ''
            # Render config from Nix attrset + secret files at runtime (keeps secrets out of git/Nix store).
            OUT=${escapeShellArg renderedConfigFile} \
            SUBS_JSON=${escapeShellArg subsJson} \
            CONFIG_JSON=${escapeShellArg configJson} \
            ${pkgs.python3}/bin/python3 - <<'PY'
            import json
            import os
            from pathlib import Path

            template = os.environ["CONFIG_JSON"]
            subs = json.loads(os.environ["SUBS_JSON"])

            for placeholder, secret_path in subs.items():
                val = Path(secret_path).read_text(encoding="utf-8").strip()
                template = template.replace(placeholder, val)

            out_path = Path(os.environ["OUT"])
            out_path.write_text(template, encoding="utf-8")
            os.chmod(out_path, 0o400)
            PY
          ''}

          exec ${pkgs.gallery-dl-custom-fixed}/bin/gallery-dl ${escapeShellArgs args}
        '';
      })
    enabledInstances;

    systemd.timers = mapAttrs' (name: inst:
      nameValuePair "gallery-dl-${name}" {
        description = "gallery-dl timer: ${name}";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = inst.onCalendar;
          Persistent = true;
          Unit = "gallery-dl-${name}.service";
        };
      })
    enabledInstances;

    # --------------------------------------------------------------------------
    # PACKAGE INSTALLATION
    # --------------------------------------------------------------------------

    environment.systemPackages = [
      pkgs.gallery-dl-custom-fixed
      # Telegram exporter dependency (python Telethon)
      (pkgs.python3.withPackages (ps: [
        ps.telethon
      ]))
    ];
  };
}
