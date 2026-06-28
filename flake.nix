{
  description = "Firefox with V4L2 H.264 hardware decode patches for NVIDIA/nixling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      manifest = builtins.fromJSON (builtins.readFile ./nix/prebuilt.json);
      firefoxVersion = "152.0.2";
      firefoxPolicies = {
        Preferences = {
          "media.hardware-video-decoding.enabled" = {
            Status = "locked";
            Value = true;
          };
          "media.hardware-video-decoding.force-enabled" = {
            Status = "locked";
            Value = true;
          };
          "media.ffmpeg.enabled" = {
            Status = "locked";
            Value = true;
          };
          "media.rdd-ffmpeg.enabled" = {
            Status = "locked";
            Value = true;
          };
          "media.ffmpeg.disable-software-fallback" = {
            Status = "locked";
            Value = false;
          };
        };
      };
      policiesJson = pkgs.writeText "firefox-policies.json" (builtins.toJSON {
        policies = firefoxPolicies;
      });
      hasPrebuilt = manifest.version != null
        && manifest.binaries ? "firefox-v4l2-nvidia"
        && system == manifest.system;
      defaultOverrideArgs = {
        extraPrefsFiles = [];
        nativeMessagingHosts = [];
        cfg = {};
      };
      resolveOverrideArgs = override:
        if builtins.isFunction override
        then override defaultOverrideArgs
        else override;
      nativeMessagingHostLinks = hosts:
        let
          hostBins = map lib.getBin (lib.unique hosts);
        in lib.optionalString (hostBins != []) ''
          mkdir -p $out/lib/mozilla/native-messaging-hosts
          for host in ${lib.escapeShellArgs (map toString hostBins)}; do
            for manifest in "$host"/lib/mozilla/native-messaging-hosts/*; do
              [ -e "$manifest" ] || continue
              ln -sLt "$out/lib/mozilla/native-messaging-hosts" "$manifest"
            done
          done
        '';

      prebuiltPackage = pkgs.stdenv.mkDerivation {
        pname = "firefox-v4l2-nvidia";
        version = manifest.version;
        src = pkgs.fetchurl {
          inherit (manifest.binaries."firefox-v4l2-nvidia") url hash;
        };
        nativeBuildInputs = with pkgs; [ autoPatchelfHook makeWrapper wrapGAppsHook3 ];
        buildInputs = with pkgs; [
          stdenv.cc.cc.lib gtk3 glib dbus-glib libXt alsa-lib
          pulseaudio ffmpeg libGL pango atk gdk-pixbuf cairo
          fontconfig freetype libxkbcommon wayland
          nspr nss_latest cups libdrm mesa libva protobuf
          xorg.libX11 xorg.libXcomposite xorg.libXdamage xorg.libXext
          xorg.libXfixes xorg.libXrandr xorg.libxcb
        ];
        sourceRoot = ".";
        dontConfigure = true;
        dontBuild = true;
        dontWrapGApps = true;
        installPhase = ''
          mkdir -p $out
          cp -a bin lib share $out/ 2>/dev/null || true
          cp -a lib $out/ 2>/dev/null || true
          cp -a bin $out/ 2>/dev/null || true
        '';
        postFixup = ''
          rm -f $out/bin/firefox $out/bin/.firefox-wrapped $out/bin/.firefox-wrapped_
          makeWrapper $out/lib/firefox/firefox $out/bin/firefox \
            --set MOZ_SYSTEM_DIR "$out/lib/mozilla" \
            --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ pkgs.nss_latest ]}
          install -Dm644 ${policiesJson} $out/lib/firefox/distribution/policies.json
          wrapGApp $out/bin/firefox
        '';
        passthru = {
          # programs.firefox NixOS module calls package.override to inject
          # extraPrefsFiles, nativeMessagingHosts, and cfg. Accept those
          # and re-derive with the additions applied.
          override = overrideFn: let
            args = resolveOverrideArgs overrideFn;
          in prebuiltPackage.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [])
              ++ (args.nativeMessagingHosts or []);
            installPhase = (old.installPhase or "") + ''
              ${builtins.concatStringsSep "\n" (map (f:
                "install -Dm644 ${f} $out/lib/firefox/defaults/pref/$(basename ${f})"
              ) (args.extraPrefsFiles or []))}
              ${nativeMessagingHostLinks (args.nativeMessagingHosts or [])}
            '';
          });
          version = manifest.version;
        };
        meta = {
          description = "Firefox with V4L2 H.264 hardware decode (pre-built)";
          mainProgram = "firefox";
          platforms = [ system ];
        };
      };

      firefoxUnwrapped = (pkgs.firefox-unwrapped.override {
        pgoSupport = false;
        ltoSupport = false;
        enableDebugSymbols = false;
      }).overrideAttrs (old: {
        version = firefoxVersion;
        src = self;
        passthru = (old.passthru or {}) // {
          version = firefoxVersion;
        };
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.sccache ];
        SCCACHE_DIR = "/var/cache/nixling-firefox-sccache";
        SCCACHE_MAX_FRAME_LENGTH = "104857600";
        MOZ_USING_SCCACHE = "1";
        RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
      });

      sourcePackage = (pkgs.wrapFirefox firefoxUnwrapped {
        extraPolicies = firefoxPolicies;
      }).overrideAttrs (old: {
        version = firefoxVersion;
        passthru = (old.passthru or {}) // {
          version = firefoxVersion;
        };
      });

      dummyNativeMessagingHost = pkgs.runCommand "dummy-native-messaging-host" {} ''
        mkdir -p $out/bin $out/lib/mozilla/native-messaging-hosts
        cat > $out/bin/dummy-native-messaging-host <<'EOF'
        #!${pkgs.runtimeShell}
        exit 0
        EOF
        chmod +x $out/bin/dummy-native-messaging-host
        cat > $out/lib/mozilla/native-messaging-hosts/dummy_native_host.json <<EOF
        {
          "name": "dummy_native_host",
          "description": "Dummy native messaging host for wrapper validation",
          "path": "$out/bin/dummy-native-messaging-host",
          "type": "stdio",
          "allowed_extensions": [ "dummy@example.com" ]
        }
        EOF
      '';
      nativeMessagingHostCheckPackage = prebuiltPackage.override (_: {
        nativeMessagingHosts = [ dummyNativeMessagingHost ];
      });
    in {
      packages.${system} = {
        default = if hasPrebuilt then prebuiltPackage else sourcePackage;
        source = sourcePackage;
        unwrapped = firefoxUnwrapped;
      };
      checks.${system} = {
        native-messaging-hosts = pkgs.runCommand
          "firefox-native-messaging-hosts-check"
          {}
          ''
            test -e ${nativeMessagingHostCheckPackage}/lib/mozilla/native-messaging-hosts/dummy_native_host.json
            ${pkgs.binutils}/bin/strings ${nativeMessagingHostCheckPackage}/bin/.firefox-wrapped | grep -q 'MOZ_SYSTEM_DIR'
            ${pkgs.binutils}/bin/strings ${nativeMessagingHostCheckPackage}/bin/.firefox-wrapped | grep -q '/lib/mozilla'
            touch $out
          '';
        software-fallback-policy = pkgs.runCommand
          "firefox-software-fallback-policy-check"
          {}
          ''
            ${pkgs.jq}/bin/jq -e \
              '.policies.Preferences."media.ffmpeg.disable-software-fallback".Value == false' \
              ${prebuiltPackage}/lib/firefox/distribution/policies.json
            touch $out
          '';
      };
    };
}
