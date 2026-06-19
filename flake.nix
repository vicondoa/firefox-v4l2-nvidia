{
  description = "Firefox with V4L2 H.264 hardware decode patches for NVIDIA/nixling";

  nixConfig = {
    extra-substituters = [ "https://vicondoa.github.io/firefox-v4l2-nvidia" ];
    extra-trusted-public-keys = [ "vicondoa-firefox-v4l2-nvidia:CYUcfzuGgZEx/Eg7ARpP/kE0SiU2bDhU0I3C3tw99fY=" ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      firefoxUnwrapped = (pkgs.firefox-unwrapped.override {
        pgoSupport = false;
        ltoSupport = false;
        enableDebugSymbols = false;
      }).overrideAttrs (old: {
        version = "152.0";
        src = self;

        # sccache: persistent compiler cache for C/C++/Rust. Cuts
        # rebuild time from ~2h to ~15min when only patches change.
        # Requires the host to expose the cache dir into the Nix
        # sandbox via nix.settings.extra-sandbox-paths (see
        # /etc/nixos/configuration.nix). CI uses flakehub-cache
        # instead (caches the entire /nix/store).
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.sccache ];
        SCCACHE_DIR = "/var/cache/nixling-firefox-sccache";
        SCCACHE_MAX_FRAME_LENGTH = "104857600";
        MOZ_USING_SCCACHE = "1";
        RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
      });
    in {
      packages.${system} = {
        unwrapped = firefoxUnwrapped;
        default = pkgs.wrapFirefox firefoxUnwrapped {
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
        };
      };
    };
}
