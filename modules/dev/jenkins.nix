{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.dev.jenkins;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.dev.jenkins = {
    enable = mkEnableOption "Jenkins CI/CD server";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for Jenkins web interface";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address for Jenkins to listen on";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # JENKINS SERVICE
    # --------------------------------------------------------------------------

    services.jenkins = {
      enable = true;
      listenAddress = cfg.listenAddress;
      port = cfg.port;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
