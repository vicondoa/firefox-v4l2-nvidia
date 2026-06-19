{
  description = "Firefox with V4L2 H.264 hardware decode patches for NVIDIA/nixling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      firefoxUnwrapped = (pkgs.firefox-unwrapped.override {
        pgoSupport = false;
        ltoSupport = false;
        enableDebugSymbols = false;
      }).overrideAttrs (_old: {
        version = "152.0";
        src = self;
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
