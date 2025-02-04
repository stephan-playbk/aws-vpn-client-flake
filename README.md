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

### Override the version

```nix
programs.awsvpnclient.enable = true;
programs.awsvpnclient.version = "3.15.0";
programs.awsvpnclient.sha256 = "5cf3eb08de96821b0ad3d0c93174b2e308041d5490a3edb772dfd89a6d89d012";
```

OR 


```nix
let awsVpnClient = aws-vpn-client.packages.x86_64-linux.awsvpnclient.overrideVersion {version = "3.15.0"; sha256 = "5cf3eb08de96821b0ad3d0c93174b2e308041d5490a3edb772dfd89a6d89d012"; };
environment.systemPackages = [ awsVpnClient ];
systemd.packages = [ awsVpnClient ];
systemd.services.AwsVpnClientService.wantedBy = [ "multi-user.target" ];
```

### Build locally
```shell
# Insecure because of its usage of `openssl-1.1.1w`
export NIXPKGS_ALLOW_INSECURE=1
nix build --impure
```

### Special thanks
- https://github.com/BOPOHA/aws-rpm-packages
