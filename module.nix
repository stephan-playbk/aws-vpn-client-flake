{ inputs, system, ... }:

{ lib, config, ... }:

with lib;

let cfg = config.programs.awsvpnclient;
in {
  options.programs.awsvpnclient.enable = mkEnableOption "Enable AWS VPN Client";

  config = mkIf cfg.enable {
    environment.systemPackages =
      [ inputs.self.packages.${system}.awsvpnclient ];
    systemd.packages = [ inputs.self.packages.${system}.awsvpnclient ];

    # Even though the service already defines this, nixos doesn't pick that up and leaves the service disabled
    systemd.services.AwsVpnClientService.wantedBy = [ "multi-user.target" ];
  };
}
