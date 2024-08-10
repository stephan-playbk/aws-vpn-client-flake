{ lib, pkgs, stdenv, fetchurl, buildFHSEnv, autoPatchelfHook, copyDesktopItems
, makeDesktopItem, libredirect, ... }:

let
  pname = "awsvpnclient";
  versionInfo = import ./version.nix;
  srcVersion = versionInfo.version;
  srcHash = versionInfo.sha256;
  srcUrl =
    "https://d20adtppz83p9s.cloudfront.net/GTK/${srcVersion}/awsvpnclient_amd64.deb";

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

  # https://github.com/BOPOHA/aws-rpm-packages/tree/d9df3adf679a7e0f04e13d493085b24dc80b9cc3
  patchPrefix =
    "https://raw.githubusercontent.com/BOPOHA/aws-rpm-packages/d9df3adf679a7e0f04e13d493085b24dc80b9cc3/awsvpnclient";
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
  ];

  deb = stdenv.mkDerivation ({
    pname = "${pname}-deb";
    version = srcVersion;

    src = fetchurl {
      url = srcUrl;
      sha256 = srcHash;
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
        patch -p1 < tmp.patch
        rm tmp.patch
      '') fetchedPatches)}
      cd "$out"

      # Rename to something more "linux-y"
      mv "$out/${debGuiExe}" "$out/${guiExe}"

      ${wrapExeWithRedirects "$out/${serviceExe}"}
    '';
  });

  serviceFHS = buildFHSEnv {
    name = "${pname}-service-wrapped";
    version = srcVersion;

    runScript = "${serviceExe}";
    targetPkgs = _: [ deb ];

    extraBwrapArgs = [
      # Service exe uses this as it's temp directory
      "--tmpfs /opt/awsvpnclient/Resources"

      # For some reason, I can't do this with the redirect as I did above
      "--tmpfs /sbin"
      "--ro-bind /${pkgs.iproute2}/bin/ip /sbin/ip"
    ];

    multiPkgs = _: with pkgs; [ openssl_1_1 icu70 ];
  };

  desktopItem = (makeDesktopItem {
    name = pname;
    desktopName = "AWS VPN Client";
    exec = "${guiFHS.name} %u";
    icon = "${deb}/usr/share/pixmaps/acvc-64.png";
    categories = [ "Network" "X-VPN" ];
  });

  guiFHS = buildFHSEnv {
    name = "${pname}-wrapped";
    version = srcVersion;

    runScript = "${guiExe}";
    targetPkgs = _: [ deb ];

    multiPkgs = _: with pkgs; [ openssl_1_1 icu70 gtk3 ];

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
in guiFHS
