{
  description = "Firefox with V4L2 H.264 hardware decode patches for NVIDIA/nixling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      manifest = builtins.fromJSON (builtins.readFile ./nix/prebuilt.json);
      firefoxVersion = "152.0.2";
      hasPrebuilt = manifest.version != null
        && builtins.match "v${firefoxVersion}-nixling\\..*" manifest.version != null
        && manifest.binaries ? "firefox-v4l2-nvidia"
        && system == manifest.system;

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
            --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ pkgs.nss_latest ]}
          wrapGApp $out/bin/firefox
        '';
        passthru = {
          # programs.firefox NixOS module calls package.override to inject
          # extraPrefsFiles, nativeMessagingHosts, and cfg. Accept those
          # and re-derive with the additions applied.
          override = overrideFn: let
            args = overrideFn {
              extraPrefsFiles = [];
              nativeMessagingHosts = [];
              cfg = {};
            };
          in prebuiltPackage.overrideAttrs (old: {
            buildCommand = old.buildCommand or "";
            nativeBuildInputs = (old.nativeBuildInputs or [])
              ++ (args.nativeMessagingHosts or []);
            postInstall = (old.postInstall or "") + ''
              ${builtins.concatStringsSep "\n" (map (f:
                "install -Dm644 ${f} $out/lib/firefox/defaults/pref/$(basename ${f})"
              ) (args.extraPrefsFiles or []))}
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
        extraPolicies.Preferences = {
          "media.ffmpeg.v4l2-m2m.enabled" = {
            Status = "locked";
            Value = true;
          };
          "media.ffmpeg.vaapi.enabled" = {
            Status = "locked";
            Value = false;
          };
          "media.ffmpeg.vaapi.force-enabled" = {
            Status = "locked";
            Value = false;
          };
        };
      }).overrideAttrs (old: {
        version = firefoxVersion;
        passthru = (old.passthru or {}) // {
          version = firefoxVersion;
        };
      });
    in {
      packages.${system} = {
        default = if hasPrebuilt then prebuiltPackage else sourcePackage;
        source = sourcePackage;
        unwrapped = firefoxUnwrapped;
      };
    };
}
