# ============================================================================
# FLEET HOST DEFINITIONS
# ============================================================================
{
  galadriel = {
    ip = "192.168.2.3";
    user = "dominik";
    tags = [
      "control-plane"
      "monitoring"
    ];
  };

  frodo = {
    ip = "192.168.2.11";
    user = "dominik";
    tags = [
      "git"
    ];
  };

  sam = {
    ip = "192.168.2.12";
    user = "dominik";
    tags = [];
  };

  elrond = {
    user = "dominik";
    tags = [
      "wsl"
      "development"
    ];
  };
}
