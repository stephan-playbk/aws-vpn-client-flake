{ lib, pkgs, stdenv, fetchurl, buildFHSEnv, autoPatchelfHook, copyDesktopItems
, makeDesktopItem, libredirect, ... }:

let
  pname = "awsvpnclient";

  srcUrl = versionInfo:
    "https://d20adtppz83p9s.cloudfront.net/GTK/${versionInfo.version}/awsvpnclient_amd64.deb";

  exePrefix = "/opt/awsvpnclient";
  debGuiExe = "${exePrefix}/AWS VPN Client";
  guiExe = "${exePrefix}/awsvpnclient";
  serviceExe = "${exePrefix}/Service/ACVC.GTK.Service";

  wrapExeWithRedirects = exe: ''
    wrapProgram "${exe}" \
        --set LD_PRELOAD "${libredirect}/lib/libredirect.so" \
        --set NIX_REDIRECTS "${
          lib.concatStringsSep ":"
          (map (redir: "${redir.dest}=${redir.src}") serviceRedirects)
        }"
  '';

  # https://github.com/BOPOHA/aws-rpm-packages/tree/438f57079cecbc07ce9d99af85430d6c777e62c6
  patchPrefix =
    "https://raw.githubusercontent.com/BOPOHA/aws-rpm-packages/438f57079cecbc07ce9d99af85430d6c777e62c6/awsvpnclient";
  patchInfos = [
    {
      url = "${patchPrefix}/acvc.gtk..deps.patch";
      sha256 = "sha256-z3FFNj/Pk6EDkhiysqG2OlH9sLGaxSXNMRd1hQlRmeE=";
    }
    {
      url = "${patchPrefix}/awsvpnclient.deps.patch";
      sha256 = "sha256-+8J3Tp5UzqW+80bTcdid3bmLhci1dTsDAf6RakfRcDw=";
    }
  ];

  fetchedPatches = map (patch:
    fetchurl {
      url = patch.url;
      sha256 = patch.sha256;
    }) patchInfos;

  myIpBin = pkgs.writeShellScript "fix_aws_ip_call.sh" ''
    args=("$@")
    arg1=''${args[0]}
    arg2=''${args[1]}
    arg3=''${args[2]}
    arg4=''${args[3]}
    arg5=''${args[4]}
    arg6=''${args[5]}

    # expected args: 'addr' 'add' 'dev' 'tun0' <ip> 'broadcast' <ip>
    # if 'broadcast' is missing, calculate it
    if [ "$arg1" = 'addr' ] && [ "$arg2" = 'add' ] && [ "$arg3" = 'dev' ] && [ "$arg4" = 'tun0' ] && [ -z "$arg6" ]; then
      export $(${pkgs.ipcalc}/bin/ipcalc $arg5 -b)
      ${pkgs.iproute2}/bin/ip "''${args[@]}" broadcast $BROADCAST
    else
      ${pkgs.iproute2}/bin/ip "$@"
    fi
  '';

  serviceRedirects = [
    {
      src = "${pkgs.ps}/bin/ps";
      dest = "/bin/ps";
    }
    {
      src = "${pkgs.lsof}/bin/lsof";
      dest = "/usr/bin/lsof";
    }
    {
      src = "${pkgs.sysctl}/bin/sysctl";
      dest = "/sbin/sysctl";
    }
    {
      src = myIpBin;
      dest = "/sbin/ip";
    }
  ];

  mkDeb = versionInfo:
    stdenv.mkDerivation ({
      pname = "${pname}-deb";
      version = versionInfo.version;

      src = fetchurl {
        url = srcUrl versionInfo;
        sha256 = versionInfo.sha256;
      };

      nativeBuildInputs = [ autoPatchelfHook pkgs.makeWrapper ];

      unpackPhase = ''
        ${pkgs.dpkg}/bin/dpkg -x "$src" unpacked
        mkdir -p "$out"
        cp -r unpacked/* "$out/"
        addAutoPatchelfSearchPath "$out/${exePrefix}"
        addAutoPatchelfSearchPath "$out/${exePrefix}/Service"
        addAutoPatchelfSearchPath "$out/${exePrefix}/Service/Resources/openvpn"
      '';

      fixupPhase = ''
        # Workaround for missing compatibility of the SQL library, intentionally breaking the metrics agent
        # It will be unable to load the dynamic lib and will start, but with error message
        rm "$out/opt/awsvpnclient/SQLite.Interop.dll"

        # Apply source patches
        cd "$out/opt/awsvpnclient"
        ${lib.concatStringsSep "\n" (map (patch: ''
          cp ${patch} tmp.patch
          sed -i -E 's|([+-]{3}) (\")?/opt/awsvpnclient/|\1 \2./|g' tmp.patch
          patch -p1 < tmp.patch || cat *.rej
          rm tmp.patch
        '') fetchedPatches)}
        cd "$out"

        # Rename to something more "linux-y"
        mv "$out/${debGuiExe}" "$out/${guiExe}"

        ${wrapExeWithRedirects "$out/${serviceExe}"}
      '';
    });

  mkServiceFHS = { versionInfo, deb }:
    buildFHSEnv {
      name = "${pname}-service-wrapped";
      version = versionInfo.version;

      runScript = "${serviceExe}";
      targetPkgs = _: [ deb ];

      extraBwrapArgs = [
        # Service exe uses this as it's temp directory
        "--tmpfs /opt/awsvpnclient/Resources"

        # For some reason, I can't do this with the redirect as I did above
        "--tmpfs /usr/sbin"
        "--ro-bind ${myIpBin} /usr/sbin/ip"
      ];

      multiPkgs = _:
        with pkgs;
        [
          # TODO: This still nessesary?
          #openssl_1_1
          icu70
        ];
    };

  mkDesktopItem = { versionInfo, deb }:
    (makeDesktopItem {
      name = pname;
      desktopName = "AWS VPN Client";
      exec = "${(guiFHS versionInfo).name} %u";
      icon = "${deb}/usr/share/pixmaps/acvc-64.png";
      categories = [ "Network" "X-VPN" ];
    });

  guiFHS = versionInfo:
    let
      deb = mkDeb versionInfo;
      serviceFHS = (mkServiceFHS { inherit versionInfo deb; });
      desktopItem = (mkDesktopItem { inherit versionInfo deb; });
    in buildFHSEnv {
      name = "${pname}-wrapped";
      version = versionInfo.version;

      runScript = "${guiExe}";
      targetPkgs = _: [ deb ];

      multiPkgs = _:
        with pkgs; [
          # TODO: This still nessesary?
          # openssl_1_1

          icu70
          gtk3
        ];

      extraBwrapArgs = [
        # For some reason, I can't do this with the redirect as I did above
        "--tmpfs /usr/sbin"
        "--ro-bind ${myIpBin} /usr/sbin/ip"
      ];

      extraInstallCommands = ''
        mkdir -p "$out/lib/systemd/system"
        cat <<EOF > "$out/lib/systemd/system/AwsVpnClientService.service"
        [Service]
        Type=simple
        ExecStart=${serviceFHS}/bin/${serviceFHS.name}
        Restart=always
        RestartSec=1s
        User=root

        [Install]
        WantedBy=multi-user.target
        EOF

        mkdir -p "$out/share/applications"
        cp "${desktopItem}/share/applications/${pname}.desktop" "$out/share/applications/${pname}.desktop"
      '';
    };

  # Why do I gotta make my own thing? .override doesn't work!?
  makeOverridable = f: origArgs:
    let origRes = f origArgs;
    in origRes // { overrideVersion = newArgs: (f (origArgs // newArgs)); };
in makeOverridable guiFHS (import ./version.nix)
