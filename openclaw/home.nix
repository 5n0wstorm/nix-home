# ============================================================================
# OpenClaw - Home Manager config (shared for Linux and Darwin)
# ============================================================================
# Fill in: gateway.auth.token, channels.telegram.tokenFile, allowFrom.
# See https://github.com/openclaw/nix-openclaw and docs at https://docs.openclaw.ai/install/nix
# ============================================================================

{config, pkgs, ...}: {
  home.username = "dominik";
  home.homeDirectory =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/Users/dominik"
    else "/home/dominik";
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  programs.openclaw = {
    documents = ./documents;

    config = {
      gateway = {
        mode = "local";
        auth = {
          # REPLACE: long random token for gateway auth (e.g. openssl rand -hex 32)
          token = "REPLACE_ME_GATEWAY_TOKEN";
        };
      };

      channels.telegram = {
        # REPLACE: path to your bot token file (e.g. ~/.secrets/openclaw-telegram-bot-token)
        tokenFile = "~/.secrets/openclaw-telegram-bot-token";
        # REPLACE: your Telegram user ID (get from @userinfobot)
        allowFrom = [];
        groups = {
          "*" = {
            requireMention = true;
          };
        };
      };
    };

    instances.default = {
      enable = true;
      plugins = [];
    };
  };
}
