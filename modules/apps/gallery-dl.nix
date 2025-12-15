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
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # DIRECTORY STRUCTURE
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      # Ensure /data/archive exists even if not provided by other modules.
      "d /data/archive 0775 root ${archiveGroup} -"

      # gallery-dl workspace (archives, downloads, metadata, etc.)
      "d ${cfg.archiveDir} 0775 root ${archiveGroup} -"
    ];

    # --------------------------------------------------------------------------
    # PACKAGE INSTALLATION
    # --------------------------------------------------------------------------

    environment.systemPackages = [
      pkgs.gallery-dl-custom
      # Telegram exporter dependency (python Telethon)
      (pkgs.python3.withPackages (ps: [
        ps.telethon
      ]))
    ];
  };
}
