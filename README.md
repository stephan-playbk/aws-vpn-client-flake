## AWS VPN Client Flake

### Flake Input
```nix
aws-vpn-client.url = "github:Polarizedions/aws-vpn-client-flake";
aws-vpn-client.inputs.nixpkgs.follows = "nixpkgs";
```
### Usage
```nix
imports = [ aws-vpn-client.nixosModules.x86_64-linux.default ];

programs.awsvpnclient.enable = true;
```

OR

```nix
environment.systemPackages = [ aws-vpn-client.packages.x86_64-linux.awsvpnclient ];
systemd.packages = [ aws-vpn-client.packages.x86_64-linux.awsvpnclient ];
systemd.services.AwsVpnClientService.wantedBy = [ "multi-user.target" ];
```

### Build locally
```shell
# Insecure because of its usage of `openssl-1.1.1w`
export NIXPKGS_ALLOW_INSECURE=1
nix build --impure
```
