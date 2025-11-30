{pkgs, ...}: {
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../modules/monitoring/node-exporter.nix
    ../modules/dev/rebuild.nix
    ../modules/system/motd.nix
  ];
  # ============================================================================
  # NIX CONFIGURATION
  # ============================================================================

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = ["@wheel"];

      # Resource limits to prevent OOM during builds
      max-jobs = 4; # Max parallel derivation builds (default: auto = all cores)
      cores = 2; # Cores per build job (default: 0 = all cores)
    };
  };

  # Systemd resource limits for nix-daemon to prevent OOM
  systemd.services.nix-daemon.serviceConfig = {
    MemoryMax = "75%"; # Hard limit: kill if exceeded
    MemoryHigh = "50%"; # Soft limit: throttle at this point
    OOMScoreAdjust = 500; # Make nix-daemon more likely to be OOM-killed vs system services
  };

  # ============================================================================
  # NH - Enhanced Nix CLI Helper
  # ============================================================================

  programs.nh = {
    enable = true;
    flake = "/home/dominik/nix-home"; # Default flake path for nh commands
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep 5 --keep-since 7d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.dominik = {
    isNormalUser = true;
    description = "Bossman himself";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2kCBJfIsSKVFC6F002SV5MrGzy6vld+ltC2SzWTugx boss@chef.com"
    ];
  };

  # ============================================================================
  # SECURITY
  # ============================================================================

  security.sudo.wheelNeedsPassword = false;

  # ============================================================================
  # NETWORKING
  # ============================================================================

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [22];

  # ============================================================================
  # SERVICES
  # ============================================================================

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };

  # --------------------------------------------------------------------------
  # MONITORING
  # --------------------------------------------------------------------------

  fleet.monitoring.nodeExporter.enable = true;

  # --------------------------------------------------------------------------
  # DEVELOPMENT TOOLS
  # --------------------------------------------------------------------------

  fleet.dev.rebuild.enable = true;

  # --------------------------------------------------------------------------
  # SYSTEM
  # --------------------------------------------------------------------------

  fleet.system.motd.enable = true;

  # ============================================================================
  # PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    git
    wget
    htop
    neofetch
    ncdu
    powertop
  ];

  # ============================================================================
  # LOCALIZATION & TIMEZONE
  # ============================================================================

  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # ============================================================================
  # INPUT & KEYBOARD
  # ============================================================================

  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
}
