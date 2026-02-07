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

              IMPORTANT: The generated `<workingDir>/config.json` file is overwritten on every service run.
              Manual edits to this file will NOT persist. To change the configuration, modify this option
              in your NixOS configuration and redeploy.
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

          persistent = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether the systemd timer should be persistent (catch up missed runs).
              Disabled by default to avoid triggering a long gallery-dl run during `nixos-rebuild switch`.
            '';
          };

          workingDir = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Working directory for this instance (defaults to a per-instance dir under archiveDir)";
            example = "/data/archive/gallery-dl/telegram";
          };

          useDownloadArchiveFile = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Whether to pass `--download-archive` to gallery-dl for this instance.

              If enabled, this module will pass a file path (default: `<workingDir>/archive.txt`).
              If disabled, this module will NOT pass `--download-archive`, so gallery-dl will rely on
              whatever is configured via the gallery-dl config (e.g. `extractor.archive` pointing at Postgres).
            '';
          };

          downloadArchiveFile = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Optional `--download-archive` file path. Only used when `useDownloadArchiveFile = true`.

              If null and `useDownloadArchiveFile = true`, defaults to `<workingDir>/archive.txt`.
            '';
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

    telegramChannelList = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to run the Telegram channel-list updater.";
          };
          urlFile = mkOption {
            type = types.str;
            description = "Path to the file to write channel URLs (one per line), e.g. the urlFile used by gallery-dl telegram instance.";
            example = "/data/archive/telegram/urls.txt";
          };
          apiIdPath = mkOption {
            type = types.str;
            description = "Path to file containing Telegram API ID (same as gallery-dl telegram config).";
          };
          apiHashPath = mkOption {
            type = types.str;
            description = "Path to file containing Telegram API hash.";
          };
          sessionStringPath = mkOption {
            type = types.str;
            description = "Path to file containing Telegram session string (StringSession).";
          };
          onCalendar = mkOption {
            type = types.str;
            default = "daily";
            description = "systemd OnCalendar for the channel-list updater timer.";
            example = "*-*-* 03:00:00";
          };
        };
      });
      default = null;
      description = ''
        If set, a systemd service and timer will update the given url file with all Telegram
        channels the logged-in user is part of (using the same API credentials as gallery-dl).
        Run this before or alongside gallery-dl so urls.txt stays in sync with your channel list.

        Sanity check (on the host): run the updater once, then test gallery-dl with one URL:
          systemctl start gallery-dl-telegram-channel-list.service
          cat /data/archive/telegram/urls.txt
          head -n 1 /data/archive/telegram/urls.txt | xargs gallery-dl --config /data/archive/telegram/config.json --simulate
      '';
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
        # gallery-dl workspace (archives, downloads, metadata, etc.)
        "d ${archiveBase} 2775 root ${archiveGroup} -"
        "d ${galleryDlBaseDir} 2775 root ${archiveGroup} -"
      ]
      ++ (mapAttrsToList (name: inst: let
        instanceDir =
          if inst.workingDir != null
          then inst.workingDir
          else "${galleryDlBaseDir}/${name}";
      in "d ${instanceDir} 2775 ${cfg.user} ${archiveGroup} -")
      enabledInstances);

    # --------------------------------------------------------------------------
    # SERVICES + TIMERS (multi-instance)
    # --------------------------------------------------------------------------

    systemd.services =
      # Wrapper service (triggered by timer): spawns the actual job without blocking.
      (mapAttrs' (name: _inst:
        nameValuePair "gallery-dl-${name}" {
          description = "gallery-dl instance launcher: ${name}";

          # Avoid nixos-rebuild blocking: this unit should be fast and should not be restarted automatically.
          restartIfChanged = false;

          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Group = "root";
          };

          script = ''
            set -euo pipefail

            # If a previous run is still active, don't start another one.
            if ${pkgs.systemd}/bin/systemctl -q is-active "gallery-dl-job-${name}.service"; then
              exit 0
            fi

            exec ${pkgs.systemd}/bin/systemctl start --no-block "gallery-dl-job-${name}.service"
          '';
        })
      enabledInstances)
      //
      # Actual long-running job service (does the work).
      (mapAttrs' (name: inst: let
        instanceDir =
          if inst.workingDir != null
          then inst.workingDir
          else "${galleryDlBaseDir}/${name}";
        # User requested persistent config on disk:
        # /data/archive/<instance>/config.json
        renderedConfigFile = "${instanceDir}/config.json";
        effectiveConfigFile =
          if inst.config != null
          then renderedConfigFile
          else inst.configFile;
        archiveFile =
          if inst.useDownloadArchiveFile
          then
            (
              if inst.downloadArchiveFile != null
              then inst.downloadArchiveFile
              else "${instanceDir}/archive.txt"
            )
          else null;
        args =
          (optional (effectiveConfigFile != null) "--config")
          ++ (optional (effectiveConfigFile != null) (toString effectiveConfigFile))
          ++ (optional (archiveFile != null) "--download-archive")
          ++ (optional (archiveFile != null) archiveFile)
          ++ (optional (inst.urlFile != null) "--input-file")
          ++ (optional (inst.urlFile != null) inst.urlFile)
          ++ inst.args
          ++ (optionals (inst.urlFile == null) inst.urls);
      in
        nameValuePair "gallery-dl-job-${name}" {
          description = "gallery-dl instance job: ${name}";

          # If a job is running during a switch, don't restart it (avoids blocking rebuilds).
          restartIfChanged = false;

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
              # User requested /data to be 0777 recursively.
              # Keep file writable so future runs can update it without errors.
              os.chmod(out_path, 0o666)
              PY
            ''}

            exec ${pkgs.gallery-dl-custom-fixed}/bin/gallery-dl ${escapeShellArgs args}
          '';
        }))
      enabledInstances;

    systemd.timers = mapAttrs' (name: inst:
      nameValuePair "gallery-dl-${name}" {
        description = "gallery-dl timer: ${name}";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = inst.onCalendar;
          Persistent = inst.persistent;
          Unit = "gallery-dl-${name}.service";
        };
      })
    enabledInstances;

    # --------------------------------------------------------------------------
    # TELEGRAM CHANNEL LIST UPDATER (optional)
    # --------------------------------------------------------------------------

    systemd.services.gallery-dl-telegram-channel-list = mkIf
      (cfg.enable && cfg.telegramChannelList != null && cfg.telegramChannelList.enable)
      (let
        tcl = cfg.telegramChannelList;
        urlFile = tcl.urlFile;
        apiIdPath = tcl.apiIdPath;
        apiHashPath = tcl.apiHashPath;
        sessionPath = tcl.sessionStringPath;
        pythonScript = ''
          import asyncio
          from pathlib import Path

          from telethon import TelegramClient
          from telethon.sessions import StringSession

          async def main():
              api_id = int(Path("${apiIdPath}").read_text(encoding="utf-8").strip())
              api_hash = Path("${apiHashPath}").read_text(encoding="utf-8").strip()
              session_str = Path("${sessionPath}").read_text(encoding="utf-8").strip()
              out_path = Path("${urlFile}")

              client = TelegramClient(StringSession(session_str), api_id, api_hash)
              await client.start()
              urls = []
              try:
                  async for dialog in client.iter_dialogs():
                      if not dialog.is_channel:
                          continue
                      entity = dialog.entity
                      if entity.username:
                          urls.append(f"https://t.me/{entity.username}")
                      else:
                          # Private channel/supergroup: t.me/c/<id> (strip -100 prefix)
                          cid = str(entity.id).replace("-100", "")
                          urls.append(f"https://t.me/c/{cid}")
              finally:
                  await client.disconnect()

              out_path.write_text("\n".join(sorted(urls)) + "\n", encoding="utf-8")
              out_path.chmod(0o666)

          asyncio.run(main())
        '';
      in {
        description = "Update Telegram channel list for gallery-dl urls.txt";

        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = cfg.group;
          SupplementaryGroups = optional (sharedMediaCfg.enable or false) archiveGroup;
        };

        script = ''
          exec ${pkgs.python3.withPackages (ps: [ ps.telethon ])}/bin/python -c ${escapeShellArg pythonScript}
        '';
      });

    systemd.timers.gallery-dl-telegram-channel-list =
      mkIf (cfg.enable && cfg.telegramChannelList != null && cfg.telegramChannelList.enable) {
        description = "Timer: update Telegram channel list for gallery-dl";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = cfg.telegramChannelList.onCalendar;
          Persistent = true;
          Unit = "gallery-dl-telegram-channel-list.service";
        };
      };

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
