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

    applyMtimeFromMetadata = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to pass `--mtime <mtimeMetadataField>` to all gallery-dl instances.
        This sets downloaded files' mtime from gallery metadata (for example post date)
        instead of HTTP Last-Modified headers.
      '';
    };

    mtimeMetadataField = mkOption {
      type = types.str;
      default = "date";
      description = ''
        Metadata key selector passed to `--mtime` (for example `date` or `status[date]`).
        Only used when `applyMtimeFromMetadata = true`.
      '';
      example = "date";
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

          renderedConfigFileName = mkOption {
            type = types.str;
            default = "config.json";
            description = ''
              Filename for the rendered config when `config` is set. The file is written
              under `workingDir` and passed via `--config`.
            '';
            example = "config-replies.json";
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

          argsBeforeMtime = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              Extra CLI args passed before `--mtime <...>` (when enabled).
              Useful for per-instance ordering requirements.
            '';
            example = ["--cookies" "/data/archive/twitter/cookies.txt"];
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

          pruneEmptyDownloads = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Before each run, delete 0-byte or partial (*.part) media files under
              `workingDir` and remove matching Postgres archive rows so gallery-dl
              will retry failed downloads instead of skipping them forever.
              Requires `@ARCHIVE_URL@` in `configSubstitutions`.

              When `pruneArchivePrefixes` is set, also removes archive rows for
              those extractor prefixes when no matching file exists under
              `workingDir` (covers failed downloads that never created a file).
            '';
          };

          pruneArchivePrefixes = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              Extractor name prefixes for orphan archive cleanup when
              `pruneEmptyDownloads` is enabled (e.g. `["bunkr" "saint" "simpcity"]`).
              Archive entries matching `prefix%` are deleted when no file under
              `workingDir` contains the entry suffix (the part after the last `_`).
            '';
            example = ["bunkr" "saint" "simpcity"];
          };

          httpProxy = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              HTTP proxy URL for this instance (e.g. Gluetun on http://127.0.0.1:8888).
              Used for a curl-impersonate DDoS-Guard warmup and as HTTPS_PROXY for gallery-dl.
            '';
            example = "http://127.0.0.1:8888";
          };

          impersonateWarmupUrl = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              If set, hit this URL with curl-impersonate (Chrome TLS) before gallery-dl
              to refresh DDoS-Guard cookies for the current egress IP.
            '';
            example = "https://simpcity.cr/";
          };

          impersonateCookiesPath = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Cookie jar updated by impersonateWarmupUrl (Netscape format).";
            example = "/mnt/hetzner/archive/simpcity/cookies.txt";
          };

          challengeSolverUrl = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              FlareSolverr `/v1` endpoint. When set with impersonateCookiesPath,
              solve the DDoS-Guard JS challenge in a real browser and merge the
              resulting cookies into the jar before gallery-dl runs.
            '';
            example = "http://127.0.0.1:8191/v1";
          };

          skipIfChallengeCookiesExpired = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Skip the run when `__ddg5_` is missing or expired so a stale
              DDoS-Guard jar does not 403 every URL (and escalate to captcha).
              Requires impersonateCookiesPath.
            '';
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
          urlLogFile = mkOption {
            type = types.str;
            default = "/data/archive/telegram/url-logs.txt";
            description = "Path to append added/deleted URL diffs when the channel list changes.";
            example = "/data/archive/telegram/url-logs.txt";
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
        Only updates the file when the list changes; added/deleted URLs are appended to urlLogFile.

        Sanity check (on the host): run the updater once, then test gallery-dl with one URL:
          systemctl start gallery-dl-telegram-channel-list.service
          cat /data/archive/telegram/urls.txt
          head -n 1 /data/archive/telegram/urls.txt | xargs gallery-dl --config /data/archive/telegram/config.json --simulate
      '';
    };

    twitterFollowingList = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to run the Twitter following-list updater.";
          };
          urlFile = mkOption {
            type = types.str;
            description = "Path to the file to write media URLs (one per line), e.g. the urlFile used by gallery-dl twitter instance. Each URL is https://x.com/<username>/media.";
            example = "/data/archive/twitter/urls.txt";
          };
          cookiesPath = mkOption {
            type = types.str;
            description = "Path to the cookies file for the Twitter account (same as gallery-dl twitter instance).";
            example = "/data/archive/twitter/cookies.txt";
          };
          twitterUsername = mkOption {
            type = types.str;
            description = "Twitter username of the logged-in account (used to fetch https://twitter.com/<username>/following).";
            example = "Siad0n";
          };
          urlLogFile = mkOption {
            type = types.str;
            default = "/data/archive/twitter/url-logs.txt";
            description = "Path to append added/deleted URL diffs when the following list changes.";
            example = "/data/archive/twitter/url-logs.txt";
          };
          onCalendar = mkOption {
            type = types.str;
            default = "daily";
            description = "systemd OnCalendar for the following-list updater timer.";
            example = "*-*-* 04:00:00";
          };
        };
      });
      default = null;
      description = ''
        If set, a systemd service and timer use gallery-dl (with cookies) to fetch the
        following list from https://twitter.com/<twitterUsername>/following and write
        https://x.com/<username>/media (one per line) to urlFile.

        Sanity check (on the host):
          systemctl start gallery-dl-twitter-following-list.service
          cat /data/archive/twitter/urls.txt
          head -n 1 /data/archive/twitter/urls.txt | xargs gallery-dl --cookies /data/archive/twitter/cookies.txt --simulate
      '';
    };

    simpcityWatchedThreadsList = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to run the SimpCity watched-threads list updater.";
          };
          urlFile = mkOption {
            type = types.str;
            description = "Path to the file to write thread URLs (one per line), e.g. the urlFile used by gallery-dl simpcity instance.";
            example = "/data/archive/simpcity/urls.txt";
          };
          cookiesPath = mkOption {
            type = types.str;
            description = "Path to the Netscape cookies file for the SimpCity account (same as gallery-dl simpcity instance).";
            example = "/data/archive/simpcity/cookies.txt";
          };
          watchedThreadsUrl = mkOption {
            type = types.str;
            default = "https://simpcity.cr/watched/threads";
            description = "SimpCity watched-threads page to enumerate.";
            example = "https://simpcity.cr/watched/threads";
          };
          urlLogFile = mkOption {
            type = types.str;
            default = "/data/archive/simpcity/url-logs.txt";
            description = "Path to append added/deleted URL diffs when the watched-threads list changes.";
            example = "/data/archive/simpcity/url-logs.txt";
          };
          onCalendar = mkOption {
            type = types.str;
            default = "daily";
            description = "systemd OnCalendar for the watched-threads updater timer.";
            example = "*-*-* 04:30:00";
          };
          httpProxy = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "HTTP proxy for watched-threads fetches (Gluetun).";
            example = "http://127.0.0.1:8888";
          };
        };
      });
      default = null;
      description = ''
        If set, a systemd service and timer fetch all watched thread URLs from
        https://simpcity.cr/watched/threads (with cookies) and write them to urlFile.

        Sanity check (on the host):
          systemctl start gallery-dl-simpcity-watched-threads-list.service
          cat /data/archive/simpcity/urls.txt
          head -n 1 /data/archive/simpcity/urls.txt | xargs gallery-dl --cookies /data/archive/simpcity/cookies.txt --simulate
      '';
    };

    simpcityDdgRefresh = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Keep a FlareSolverr Chrome session and refresh DDoS-Guard cookies.";
          };
          cookiesPath = mkOption {
            type = types.str;
            description = "Netscape cookie jar to seed and update.";
            example = "/mnt/hetzner/archive/simpcity/cookies.txt";
          };
          solverUrl = mkOption {
            type = types.str;
            default = "http://127.0.0.1:8191/v1";
            description = "FlareSolverr /v1 endpoint.";
          };
          warmupUrl = mkOption {
            type = types.str;
            default = "https://simpcity.cr/";
            description = "Page to open in the persistent Chrome session.";
          };
          sessionName = mkOption {
            type = types.str;
            default = "simpcity";
            description = "FlareSolverr session id (reused so Chrome stays warm).";
          };
          onCalendar = mkOption {
            type = types.str;
            default = "hourly";
            description = "How often to visit warmupUrl and write back __ddg* cookies.";
          };
        };
      });
      default = null;
      description = ''
        Persistent FlareSolverr session that reopens SimpCity with the current
        cookie jar. A fresh headless profile cannot mint `__ddg5_`; the same
        Chrome session can run the JS challenge when that cookie expires.
        Captcha pages are ignored and cookies.txt is left unchanged.
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
        renderedConfigFile = "${instanceDir}/${inst.renderedConfigFileName}";
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
        mtimeArgs = optionals cfg.applyMtimeFromMetadata [
          "--mtime"
          cfg.mtimeMetadataField
        ];
        ddgRefreshBeforeJob =
          cfg.simpcityDdgRefresh
          != null
          && cfg.simpcityDdgRefresh.enable
          && inst.impersonateCookiesPath != null
          && inst.impersonateCookiesPath == cfg.simpcityDdgRefresh.cookiesPath;
        args =
          (optional (effectiveConfigFile != null) "--config")
          ++ (optional (effectiveConfigFile != null) (toString effectiveConfigFile))
          ++ (optional (archiveFile != null) "--download-archive")
          ++ (optional (archiveFile != null) archiveFile)
          ++ (optional (inst.urlFile != null) "--input-file")
          ++ (optional (inst.urlFile != null) inst.urlFile)
          ++ inst.argsBeforeMtime
          ++ mtimeArgs
          ++ inst.args
          ++ (optionals (inst.urlFile == null) inst.urls);
      in
        nameValuePair "gallery-dl-job-${name}" {
          description = "gallery-dl instance job: ${name}";
          # X/Twitter DM extraction may require `node` for passcode recovery.
          path = [pkgs.nodejs pkgs.postgresql pkgs.curl-impersonate];

          # If a job is running during a switch, don't restart it (avoids blocking rebuilds).
          restartIfChanged = false;

          serviceConfig =
            {
              Type = "oneshot";
              User = cfg.user;
              Group = cfg.group;
              SupplementaryGroups = optional (sharedMediaCfg.enable or false) archiveGroup;
              WorkingDirectory = instanceDir;
              Nice = 10;
            }
            // optionalAttrs ddgRefreshBeforeJob {
              # Refresh DDoS-Guard cookies before the expiry skip check (+ runs as root).
              ExecStartPre = "+${pkgs.systemd}/bin/systemctl start gallery-dl-simpcity-ddg-refresh.service";
            }
            // optionalAttrs (inst.httpProxy != null) {
              Environment = [
                "HTTPS_PROXY=${inst.httpProxy}"
                "HTTP_PROXY=${inst.httpProxy}"
                "ALL_PROXY=${inst.httpProxy}"
                "NO_PROXY=127.0.0.1,localhost"
              ];
            };

          script = let
            subsJson = builtins.toJSON (mapAttrs (_k: v: toString v) inst.configSubstitutions);
            configJson =
              if inst.config != null
              then builtins.toJSON inst.config
              else null;
            archiveUrlFile = inst.configSubstitutions."@ARCHIVE_URL@" or null;
          in ''
            set -euo pipefail

            ${optionalString (inst.urlFile != null) ''
              # Input lists can be removed or may not have existed when the CIFS
              # archive mount was initialized. An empty list is a valid no-op run.
              ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${escapeShellArg inst.urlFile})"
              # Use a newline rather than a zero-byte file: pruneEmptyDownloads
              # deliberately removes zero-byte files before invoking gallery-dl.
              if [ ! -s ${escapeShellArg inst.urlFile} ]; then
                ${pkgs.coreutils}/bin/printf "%s\n" "" > ${escapeShellArg inst.urlFile}
              fi
            ''}

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
              try:
                  os.chmod(out_path, 0o666)
              except OSError:
                  pass
              PY
            ''}

            ${optionalString (inst.pruneEmptyDownloads && archiveUrlFile != null) ''
              # Failed downloads can leave 0-byte files while Postgres archive still
              # marks them complete — gallery-dl then skips them forever.
              if ! (
                echo "Pruning empty/partial downloads under ${instanceDir}"
                ARCHIVE_URL=$(tr -d '\n\r' < ${escapeShellArg (toString archiveUrlFile)})
                while IFS= read -r f; do
                  base=$(basename "$f")
                  id=$(printf '%s' "$base" | ${pkgs.gnugrep}/bin/grep -oE '^[0-9]+' || true)
                  case "$f" in
                    *.part)
                      stem="''${f%.part}"
                      rm -f "$f" "$stem" "$stem.json"
                      ;;
                    *)
                      rm -f "$f" "$f.json"
                      ;;
                  esac
                  if [ -n "$id" ]; then
                    pattern="twitter''${id}_%"
                    ${pkgs.postgresql}/bin/psql "$ARCHIVE_URL" -v ON_ERROR_STOP=0 \
                      -c "DELETE FROM archive WHERE entry LIKE '$pattern'" || true
                  fi
                done < <(find ${escapeShellArg instanceDir} -type f \( -size 0 -o -name '*.part' \) 2>/dev/null || true)
              ); then
                echo "Pruning empty/partial downloads failed; continuing gallery-dl run"
              fi
            ''}

            ${optionalString ((inst.pruneEmptyDownloads || false) && archiveUrlFile != null && inst.pruneArchivePrefixes != []) ''
              if ! (
                echo "Pruning orphan archive entries under ${instanceDir} for prefixes: ${lib.concatStringsSep " " inst.pruneArchivePrefixes}"
                ARCHIVE_URL=$(tr -d '\n\r' < ${escapeShellArg (toString archiveUrlFile)})
                FILE_INDEX=$(${pkgs.coreutils}/bin/mktemp)
                ORPHANS=$(${pkgs.coreutils}/bin/mktemp)
                find ${escapeShellArg instanceDir} -type f 2>/dev/null > "$FILE_INDEX" || true
                PREFIXES_JSON=${escapeShellArg (builtins.toJSON inst.pruneArchivePrefixes)} \
                ARCHIVE_URL="$ARCHIVE_URL" \
                FILE_INDEX="$FILE_INDEX" \
                ORPHANS="$ORPHANS" \
                ${pkgs.python3}/bin/python3 - <<'PY'
              import json
              import os
              import subprocess

              prefixes = json.loads(os.environ["PREFIXES_JSON"])
              archive_url = os.environ["ARCHIVE_URL"]
              file_index_path = os.environ["FILE_INDEX"]
              orphans_path = os.environ["ORPHANS"]

              with open(file_index_path, encoding="utf-8") as fh:
                  files = fh.read()

              def psql_copy(sql, data):
                  proc = subprocess.run(
                      ["psql", archive_url, "-v", "ON_ERROR_STOP=1", "-c", sql],
                      input=data,
                      text=True,
                      capture_output=True,
                  )
                  if proc.returncode != 0:
                      raise RuntimeError(proc.stderr.strip() or proc.stdout.strip())

              orphans = []
              for prefix in prefixes:
                  proc = subprocess.run(
                      ["psql", archive_url, "-t", "-A", "-c",
                       f"SELECT entry FROM archive WHERE entry LIKE '{prefix}%'"],
                      text=True,
                      capture_output=True,
                      check=True,
                  )
                  for entry in proc.stdout.splitlines():
                      if not entry:
                          continue
                      suffix = entry.rsplit("_", 1)[-1]
                      if not suffix or suffix == entry:
                          continue
                      if suffix not in files:
                          orphans.append(entry)

              if not orphans:
                  open(orphans_path, "w", encoding="utf-8").close()
              else:
                  with open(orphans_path, "w", encoding="utf-8") as fh:
                      fh.write("\n".join(orphans))
                      fh.write("\n")
                  psql_copy(
                      "CREATE TEMP TABLE orphan_entries (entry text); "
                      "COPY orphan_entries FROM STDIN; "
                      "DELETE FROM archive a USING orphan_entries o WHERE a.entry = o.entry;",
                      "\n".join(orphans) + "\n",
                  )
                  print(f"Pruned {len(orphans)} orphan archive entries")
              PY
                rm -f "$FILE_INDEX" "$ORPHANS"
              ); then
                echo "Pruning orphan archive entries failed; continuing gallery-dl run"
              fi
            ''}

            ${optionalString (inst.skipIfChallengeCookiesExpired && inst.impersonateCookiesPath != null) ''
              if ! JAR=${escapeShellArg inst.impersonateCookiesPath} \
              ${pkgs.python3}/bin/python3 - <<'PY'
              import os
              import time
              from pathlib import Path

              jar = Path(os.environ["JAR"])
              now = int(time.time())
              ddg5 = None
              if jar.exists():
                  for line in jar.read_text(encoding="utf-8", errors="replace").splitlines():
                      if not line or line.startswith("#"):
                          continue
                      parts = line.split("\t")
                      if len(parts) >= 7 and parts[5] == "__ddg5_":
                          try:
                              ddg5 = int(parts[4] or "0")
                          except ValueError:
                              ddg5 = 0
                          break
              if ddg5 is None:
                  print("DDoS-Guard cookie __ddg5_ missing; skipping gallery-dl until cookies.txt is refreshed")
                  raise SystemExit(2)
              if ddg5 > 0 and ddg5 < now:
                  print(f"DDoS-Guard cookie __ddg5_ expired ({ddg5} < {now}); skipping gallery-dl until cookies.txt is refreshed")
                  raise SystemExit(2)
              PY
              then
                exit 0
              fi
            ''}

            ${optionalString (inst.challengeSolverUrl != null && inst.impersonateCookiesPath != null && inst.impersonateWarmupUrl != null) ''
              echo "Solving DDoS-Guard challenge via FlareSolverr"
              JAR=${escapeShellArg inst.impersonateCookiesPath} \
              SOLVER=${escapeShellArg inst.challengeSolverUrl} \
              WARMUP=${escapeShellArg inst.impersonateWarmupUrl} \
              ${pkgs.python3}/bin/python3 - <<'PY'
              import json
              import os
              import urllib.error
              import urllib.request
              from pathlib import Path

              jar = Path(os.environ["JAR"])
              solver = os.environ["SOLVER"]
              url = os.environ["WARMUP"]
              payload = json.dumps({
                  "cmd": "request.get",
                  "url": url,
                  "maxTimeout": 60000,
              }).encode()
              req = urllib.request.Request(
                  solver,
                  data=payload,
                  headers={"Content-Type": "application/json"},
                  method="POST",
              )
              try:
                  with urllib.request.urlopen(req, timeout=75) as resp:
                      data = json.loads(resp.read().decode())
              except Exception as exc:
                  print(f"flaresolverr request failed: {exc}")
                  raise SystemExit(0)

              if data.get("status") != "ok":
                  print(f"flaresolverr status={data.get('status')} msg={data.get('message')}")
                  raise SystemExit(0)

              solution = data.get("solution") or {}
              cookies = solution.get("cookies") or []
              status = solution.get("status")
              html = solution.get("response") or ""
              print(f"flaresolverr page status={status} cookies={len(cookies)} msg={data.get('message')}")
              if "id=\"XF\"" not in html or "ddg-captcha-page" in html:
                  print("flaresolverr did not return XenForo HTML (captcha/challenge page); leaving cookies.txt unchanged")
                  raise SystemExit(0)
              if not cookies:
                  raise SystemExit(0)

              existing = []
              if jar.exists():
                  existing = jar.read_text(encoding="utf-8", errors="replace").splitlines()

              header = [
                  "# Netscape HTTP Cookie File",
                  "# https://curl.haxx.se/rfc/cookie_spec.html",
                  "# This is a generated file! Do not edit.",
                  "",
              ]
              kept = []
              seen = set()
              for line in existing:
                  if not line or line.startswith("#"):
                      continue
                  parts = line.split("\t")
                  if len(parts) < 7:
                      continue
                  name = parts[5]
                  if name.startswith("__ddg") or name in {"ddg_last_challenge"}:
                      continue
                  kept.append(line)
                  seen.add((parts[0], name))

              added = 0
              for ck in cookies:
                  name = ck.get("name") or ""
                  value = ck.get("value") or ""
                  domain = ck.get("domain") or ".simpcity.cr"
                  path = ck.get("path") or "/"
                  secure = "TRUE" if ck.get("secure") else "FALSE"
                  expiry = str(int(ck.get("expiry") or 0))
                  flag = "TRUE" if domain.startswith(".") else "FALSE"
                  key = (domain, name)
                  if key in seen and not (name.startswith("__ddg") or name == "ddg_last_challenge"):
                      continue
                  kept.append("\t".join([domain, flag, path, secure, expiry, name, value]))
                  seen.add(key)
                  added += 1

              jar.write_text("\n".join(header + kept) + "\n", encoding="utf-8")
              print(f"merged {added} solver cookies into {jar}")
              PY
            ''}

            # Don't fail the unit hard on extractor/runtime errors. These jobs are
            # periodic best-effort tasks and a failed run should not block
            # `nixos-rebuild switch` activation.
            if ! ${pkgs.gallery-dl-custom-fixed}/bin/gallery-dl ${escapeShellArgs args}; then
              rc=$?
              echo "gallery-dl instance '${name}' failed (exit $rc); keeping unit successful to avoid deployment failure"
              exit 0
            fi
          '';
        })
      enabledInstances)
      //
      # Telegram channel list updater (optional)
      (optionalAttrs (cfg.enable && cfg.telegramChannelList != null && cfg.telegramChannelList.enable) (let
        tcl = cfg.telegramChannelList;
        urlFile = tcl.urlFile;
        urlLogFile = tcl.urlLogFile;
        apiIdPath = tcl.apiIdPath;
        apiHashPath = tcl.apiHashPath;
        sessionPath = tcl.sessionStringPath;
        pythonScript = ''
          import asyncio
          from datetime import datetime, timezone
          from pathlib import Path

          from telethon import TelegramClient
          from telethon.sessions import StringSession

          async def main():
              api_id = int(Path("${apiIdPath}").read_text(encoding="utf-8").strip())
              api_hash = Path("${apiHashPath}").read_text(encoding="utf-8").strip()
              session_str = Path("${sessionPath}").read_text(encoding="utf-8").strip()
              out_path = Path("${urlFile}")
              log_path = Path("${urlLogFile}")

              client = TelegramClient(StringSession(session_str), api_id, api_hash)
              await client.start()
              urls = []
              try:
                  async for dialog in client.iter_dialogs():
                      entity = dialog.entity
                      if dialog.is_channel:
                          # Always use /c/<id> for channels so gallery-dl never has to resolve
                          # usernames (ResolveUsernameRequest can fail with NotFoundError/rate limits).
                          cid = str(entity.id).replace("-100", "")
                          urls.append(f"https://t.me/c/{cid}")
                      elif dialog.is_user and getattr(entity, "username", None):
                          urls.append(f"https://t.me/{entity.username}")
              finally:
                  await client.disconnect()

              new_set = set(sorted(urls))
              old_lines = out_path.read_text(encoding="utf-8").strip().splitlines() if out_path.exists() else []
              old_set = set(line.strip() for line in old_lines if line.strip())

              if new_set == old_set:
                  return

              added = new_set - old_set
              deleted = old_set - new_set
              ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
              with log_path.open("a", encoding="utf-8") as f:
                  f.write(f"--- {ts} ---\n")
                  if added:
                      f.write("added:\n")
                      for u in sorted(added):
                          f.write(f"  {u}\n")
                  if deleted:
                      f.write("deleted:\n")
                      for u in sorted(deleted):
                          f.write(f"  {u}\n")
                  f.write("\n")

              out_path.write_text("\n".join(sorted(urls)) + "\n", encoding="utf-8")
              try:
                  out_path.chmod(0o666)
              except OSError:
                  pass
              try:
                  log_path.chmod(0o666)
              except OSError:
                  pass

          asyncio.run(main())
        '';
      in {
        gallery-dl-telegram-channel-list = {
          description = "Update Telegram channel list for gallery-dl urls.txt";

          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            SupplementaryGroups = optional (sharedMediaCfg.enable or false) archiveGroup;
            RuntimeDirectory = "gallery-dl";
            RuntimeDirectoryMode = "0750";
          };

          script = ''
            exec ${pkgs.python3Packages.python.withPackages (_: [pkgs.telethonFixed])}/bin/python -c ${escapeShellArg pythonScript}
          '';
        };
      }))
      //
      # Twitter following list updater (optional): gallery-dl -g to list usernames, write x.com/<user>/media
      (optionalAttrs (cfg.enable && cfg.twitterFollowingList != null && cfg.twitterFollowingList.enable) (let
        tfl = cfg.twitterFollowingList;
        urlFile = tfl.urlFile;
        urlLogFile = tfl.urlLogFile;
        cookiesPath = tfl.cookiesPath;
        twitterUsername = tfl.twitterUsername;
        followingUrl = "https://twitter.com/${twitterUsername}/following";
      in {
        gallery-dl-twitter-following-list = {
          description = "Update Twitter following list for gallery-dl urls.txt (x.com/username/media)";

          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            SupplementaryGroups = optional (sharedMediaCfg.enable or false) archiveGroup;
            RuntimeDirectory = "gallery-dl";
            RuntimeDirectoryMode = "0750";
          };

          script = ''
            set -euo pipefail
            lockfile="/run/gallery-dl/twitter-following-list.lock"
            exec 9>"$lockfile"
            # Never run more than one updater in parallel.
            if ! ${pkgs.util-linux}/bin/flock -n 9; then
              exit 0
            fi
            out=${escapeShellArg urlFile}
            logfile=${escapeShellArg urlLogFile}
            raw=$(mktemp)
            newlist=$(mktemp)
            trap 'rm -f "$raw" "$newlist"' EXIT
            ${pkgs.gallery-dl-custom-fixed}/bin/gallery-dl \
              --cookies ${escapeShellArg cookiesPath} \
              -g \
              ${escapeShellArg followingUrl} \
              > "$raw" 2>&1 || true
            # Keep only profile-like lines and normalize to .../media.
            # gallery-dl output format has changed over time; support both
            # /i/user/<id> and /<username> style profile URLs.
            while IFS= read -r line; do
              line="''${line%%[[:space:]]*}"
              line="''${line%$'\r'}"
              line="''${line%/}"
              if [[ "$line" =~ ^https?://(twitter\.com|x\.com)/i/user/[0-9]+$ ]]; then
                echo "$line/media"
              elif [[ "$line" =~ ^https?://(twitter\.com|x\.com)/[A-Za-z0-9_]+$ ]]; then
                userpart="''${line##*/}"
                if [[ ! "$userpart" =~ ^(home|explore|notifications|message|messages|search|settings|compose|login|signup|hashtag|share|intent|i)$ ]]; then
                  echo "https://x.com/$userpart/media"
                fi
              elif [[ "$line" =~ ^https?://(twitter\.com|x\.com)/[A-Za-z0-9_]+/media$ ]]; then
                base="''${line%/media}"
                userpart="''${base##*/}"
                if [[ ! "$userpart" =~ ^(home|explore|notifications|message|messages|search|settings|compose|login|signup|hashtag|share|intent|i)$ ]]; then
                  echo "https://x.com/$userpart/media"
                fi
              fi
            done < "$raw" | sort -u > "$newlist"
            if [ ! -s ${escapeShellArg cookiesPath} ]; then
              echo "cookies file missing or empty: ${cookiesPath}" >&2
              exit 0
            fi
            if [ ! -s "$newlist" ]; then
              echo "following list fetch returned no URLs; keeping existing ${urlFile}" >&2
              exit 0
            fi
            # Only update urlFile if the list changed
            if [[ -f "$out" ]] && ${pkgs.diffutils}/bin/cmp -s "$newlist" "$out"; then
              exit 0
            fi
            # Log added and deleted URLs
            ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
            added=$(comm -23 "$newlist" <(sort "$out" 2>/dev/null || true))
            deleted=$(comm -13 "$newlist" <(sort "$out" 2>/dev/null || true))
            {
              echo "--- $ts ---"
              if [[ -n "$added" ]]; then
                echo "added:"
                echo "$added" | sed 's/^/  /'
              fi
              if [[ -n "$deleted" ]]; then
                echo "deleted:"
                echo "$deleted" | sed 's/^/  /'
              fi
              echo ""
            } >> "$logfile"
            chmod 666 "$logfile" 2>/dev/null || true
            ${pkgs.coreutils}/bin/cp "$newlist" "$out"
          '';
        };
      }))
      //
      # SimpCity watched-threads list updater (optional)
      (optionalAttrs (cfg.enable && cfg.simpcityWatchedThreadsList != null && cfg.simpcityWatchedThreadsList.enable) (let
        swl = cfg.simpcityWatchedThreadsList;
        urlFile = swl.urlFile;
        urlLogFile = swl.urlLogFile;
        cookiesPath = swl.cookiesPath;
        watchedThreadsUrl = lib.removeSuffix "/" swl.watchedThreadsUrl;
      in {
        gallery-dl-simpcity-watched-threads-list = {
          description = "Update SimpCity watched-threads list for gallery-dl urls.txt";

          restartIfChanged = false;
          path = [pkgs.curl pkgs.gnugrep pkgs.gnused pkgs.coreutils pkgs.util-linux pkgs.diffutils];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            SupplementaryGroups = optional (sharedMediaCfg.enable or false) archiveGroup;
            RuntimeDirectory = "gallery-dl";
            RuntimeDirectoryMode = "0750";
          };

          script = ''
            set -euo pipefail
            lockfile="/run/gallery-dl/simpcity-watched-threads.lock"
            exec 9>"$lockfile"
            if ! ${pkgs.util-linux}/bin/flock -n 9; then
              exit 0
            fi
            cookies=${escapeShellArg cookiesPath}
            out=${escapeShellArg urlFile}
            logfile=${escapeShellArg urlLogFile}
            base=${escapeShellArg watchedThreadsUrl}
            ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
            if [ ! -s "$cookies" ]; then
              echo "cookies file missing or empty: ${cookiesPath}" >&2
              exit 0
            fi
            newlist=$(mktemp)
            raw=$(mktemp)
            trap 'rm -f "$newlist" "$raw"' EXIT
            page=1
            while true; do
              if [ "$page" -eq 1 ]; then
                url="$base"
              else
                url="$base/page-$page"
              fi
              code=$(${pkgs.curl}/bin/curl -sS -L --max-redirs 5 -b "$cookies" -A "$ua" -o "$raw" -w "%{http_code}" "$url" || echo "000")
              if [ "$code" != "200" ]; then
                if [ "$page" -gt 1 ]; then
                  break
                fi
                echo "failed to fetch watched threads ($code) from $url" >&2
                break
              fi
              ${pkgs.gnugrep}/bin/grep -oE 'href="/threads/[^"?#]+\.[0-9]+/"' "$raw" \
                | ${pkgs.gnugrep}/bin/grep -vE 'href="/threads/(community-rules-guidelines|faq)\.[0-9]+/"' \
                | ${pkgs.gnused}/bin/sed 's#^href="##;s#"$##' \
                | ${pkgs.gnused}/bin/sed 's#^#https://simpcity.cr#' >> "$newlist"
              if ! ${pkgs.gnugrep}/bin/grep -q "pageNav-jump--next" "$raw"; then
                break
              fi
              page=$((page + 1))
            done
            sort -u "$newlist" -o "$newlist"
            if [ ! -s "$newlist" ]; then
              echo "watched threads fetch returned no URLs; keeping existing ${urlFile}" >&2
              exit 0
            fi
            if [[ -f "$out" ]] && ${pkgs.diffutils}/bin/cmp -s "$newlist" "$out"; then
              exit 0
            fi
            ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
            added=$(comm -23 "$newlist" <(sort "$out" 2>/dev/null || true))
            deleted=$(comm -13 "$newlist" <(sort "$out" 2>/dev/null || true))
            {
              echo "--- $ts ---"
              if [[ -n "$added" ]]; then
                echo "added:"
                echo "$added" | sed 's/^/  /'
              fi
              if [[ -n "$deleted" ]]; then
                echo "deleted:"
                echo "$deleted" | sed 's/^/  /'
              fi
              echo ""
            } >> "$logfile"
            chmod 666 "$logfile" 2>/dev/null || true
            ${pkgs.coreutils}/bin/cp "$newlist" "$out"
            chmod 666 "$out" 2>/dev/null || true
          '';
        };
      }))
      // (optionalAttrs (cfg.enable && cfg.simpcityDdgRefresh != null && cfg.simpcityDdgRefresh.enable) (let
        rfr = cfg.simpcityDdgRefresh;
      in {
        gallery-dl-simpcity-ddg-refresh = {
          description = "Refresh SimpCity DDoS-Guard cookies via FlareSolverr session";
          after = ["flaresolverr.service"];
          wants = ["flaresolverr.service"];
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Group = "root";
          };
          script = ''
            set -euo pipefail
            JAR=${escapeShellArg rfr.cookiesPath} \
            SOLVER=${escapeShellArg rfr.solverUrl} \
            WARMUP=${escapeShellArg rfr.warmupUrl} \
            SESSION=${escapeShellArg rfr.sessionName} \
            ${pkgs.python3}/bin/python3 - <<'PY'
            import json
            import os
            import time
            import urllib.request
            from pathlib import Path

            jar = Path(os.environ["JAR"])
            solver = os.environ["SOLVER"]
            url = os.environ["WARMUP"]
            session = os.environ["SESSION"]

            def call(payload):
                req = urllib.request.Request(
                    solver,
                    data=json.dumps(payload).encode(),
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with urllib.request.urlopen(req, timeout=90) as resp:
                    return json.loads(resp.read().decode())

            listed = call({"cmd": "sessions.list"})
            sessions = listed.get("sessions") or listed.get("session") or []
            if isinstance(sessions, str):
                sessions = [sessions]
            if session not in sessions:
                created = call({"cmd": "sessions.create", "session": session})
                print(f"session create status={created.get('status')} msg={created.get('message')}")

            cookies = []
            existing_lines = []
            if jar.exists():
                existing_lines = jar.read_text(encoding="utf-8", errors="replace").splitlines()
            old = {}
            for line in existing_lines:
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 7:
                    continue
                name = parts[5]
                old[name] = parts
                cookies.append({
                    "name": name,
                    "value": parts[6],
                    "domain": parts[0],
                    "path": parts[2],
                })

            data = call({
                "cmd": "request.get",
                "session": session,
                "url": url,
                "maxTimeout": 60000,
                "cookies": cookies,
            })
            solution = data.get("solution") or {}
            html = solution.get("response") or ""
            status = solution.get("status")
            print(f"flaresolverr status={data.get('status')} page={status} msg={data.get('message')}")
            if 'id="XF"' not in html or "ddg-captcha-page" in html:
                print("refresh skipped: no XenForo HTML (captcha/challenge)")
                raise SystemExit(0)

            now = int(time.time())
            header = [
                "# Netscape HTTP Cookie File",
                "# https://curl.haxx.se/rfc/cookie_spec.html",
                "# This is a generated file! Do not edit.",
                "",
            ]
            kept = []
            seen = set()
            for line in existing_lines:
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 7:
                    continue
                name = parts[5]
                if name.startswith("__ddg") or name == "ddg_last_challenge":
                    continue
                kept.append(line)
                seen.add((parts[0], name))

            added = 0
            rotated = []
            ddg_expiry = str(now + 3 * 3600)
            merged_ddg = set()
            for ck in solution.get("cookies") or []:
                name = ck.get("name") or ""
                if not (name.startswith("__ddg") or name == "ddg_last_challenge"):
                    continue
                value = ck.get("value") or ""
                domain = ck.get("domain") or ".simpcity.cr"
                path = ck.get("path") or "/"
                secure = "TRUE" if ck.get("secure") else "FALSE"
                expiry = ck.get("expiry")
                if not expiry:
                    prev = old.get(name)
                    if prev and prev[6] == value:
                        try:
                            old_exp = int(prev[4] or "0")
                        except ValueError:
                            old_exp = 0
                        expiry = ddg_expiry if old_exp < now else prev[4]
                    else:
                        expiry = ddg_expiry
                else:
                    try:
                        if int(expiry) < now:
                            expiry = ddg_expiry
                    except ValueError:
                        expiry = ddg_expiry
                expiry = str(int(expiry))
                flag = "TRUE" if domain.startswith(".") else "FALSE"
                kept.append("\t".join([domain, flag, path, secure, expiry, name, value]))
                seen.add((domain, name))
                merged_ddg.add(name)
                added += 1
                prev = old.get(name)
                if prev is None or prev[6] != value:
                    rotated.append(name)
                elif name == "__ddg5_" and int(expiry) >= now:
                    rotated.append("__ddg5_(extended)")

            # FlareSolverr often omits __ddg5_ from solution cookies even when XenForo loads.
            if "__ddg5_" in old and "__ddg5_" not in merged_ddg:
                prev = old["__ddg5_"]
                kept.append("\t".join([prev[0], prev[1], prev[2], prev[3], ddg_expiry, "__ddg5_", prev[6]]))
                rotated.append("__ddg5_(extended)")

            jar.write_text("\n".join(header + kept) + "\n", encoding="utf-8")
            print(f"merged {added} ddg cookies; rotated={rotated or ['none']}")
            PY
          '';
        };
      }));

    systemd.timers =
      (mapAttrs' (name: inst:
        nameValuePair "gallery-dl-${name}" {
          description = "gallery-dl timer: ${name}";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = inst.onCalendar;
            Persistent = inst.persistent;
            Unit = "gallery-dl-${name}.service";
          };
        })
      enabledInstances)
      // (optionalAttrs (cfg.enable && cfg.telegramChannelList != null && cfg.telegramChannelList.enable) {
        gallery-dl-telegram-channel-list = {
          description = "Timer: update Telegram channel list for gallery-dl";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.telegramChannelList.onCalendar;
            Persistent = true;
            Unit = "gallery-dl-telegram-channel-list.service";
          };
        };
      })
      // (optionalAttrs (cfg.enable && cfg.twitterFollowingList != null && cfg.twitterFollowingList.enable) {
        gallery-dl-twitter-following-list = {
          description = "Timer: update Twitter following list for gallery-dl";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.twitterFollowingList.onCalendar;
            Persistent = true;
            Unit = "gallery-dl-twitter-following-list.service";
          };
        };
      })
      // (optionalAttrs (cfg.enable && cfg.simpcityWatchedThreadsList != null && cfg.simpcityWatchedThreadsList.enable) {
        gallery-dl-simpcity-watched-threads-list = {
          description = "Timer: update SimpCity watched-threads list for gallery-dl";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.simpcityWatchedThreadsList.onCalendar;
            Persistent = true;
            Unit = "gallery-dl-simpcity-watched-threads-list.service";
          };
        };
      })
      // (optionalAttrs (cfg.enable && cfg.simpcityDdgRefresh != null && cfg.simpcityDdgRefresh.enable) {
        gallery-dl-simpcity-ddg-refresh = {
          description = "Timer: refresh SimpCity DDoS-Guard cookies";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.simpcityDdgRefresh.onCalendar;
            Persistent = true;
            Unit = "gallery-dl-simpcity-ddg-refresh.service";
          };
        };
      });

    # --------------------------------------------------------------------------
    # PACKAGE INSTALLATION
    # --------------------------------------------------------------------------

    environment.systemPackages = [
      pkgs.gallery-dl-custom-fixed
      # Required by Twitter/X DM passcode recovery in gallery-dl.
      pkgs.nodejs
      # Telegram exporter dependency (python Telethon)
      (pkgs.python3Packages.python.withPackages (_: [
        pkgs.telethonFixed
      ]))
    ];
  };
}
