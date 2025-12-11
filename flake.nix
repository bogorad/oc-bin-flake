{
  description = "Self-updating SST OpenCode wrapper (Universal)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # --- CONFIGURATION ---

        # 1. Architecture & Asset Mapping
        # Map Nix system -> SST Release Asset Name
        # Note: Darwin assets are .zip, Linux are .tar.gz
        config =
          {
            "x86_64-linux" = {
              arch = "linux-x64-musl";
              ext = "tar.gz";
            };
            "aarch64-linux" = {
              arch = "linux-arm64-musl";
              ext = "tar.gz";
            };
            "aarch64-darwin" = {
              arch = "darwin-arm64";
              ext = "zip";
            };
            "x86_64-darwin" = {
              arch = "darwin-x64";
              ext = "zip";
            };
          }
          .${system} or (throw "Unsupported system: ${system}");

        # 2. Linux-Only Dependencies (RPATH / Interpreter)
        isLinux = pkgs.stdenv.isLinux;

        # Musl libs (only relevant for Linux)
        linuxRuntimeLibs =
          if isLinux then
            pkgs.lib.makeLibraryPath [
              pkgs.musl
              pkgs.pkgsMusl.stdenv.cc.cc.lib
              pkgs.pkgsMusl.zlib
            ]
          else
            "";

        # Dynamic Linker (only relevant for Linux)
        linuxInterpreter =
          if system == "x86_64-linux" then
            "${pkgs.musl}/lib/ld-musl-x86_64.so.1"
          else if system == "aarch64-linux" then
            "${pkgs.musl}/lib/ld-musl-aarch64.so.1"
          else
            "";

        # 3. Wrapper Script
        opencode-wrapper = pkgs.writeShellApplication {
          name = "opencode";
          runtimeInputs =
            with pkgs;
            [
              curl
              jq
              file
              gnugrep
            ]
            ++ (
              if isLinux then
                [
                  gnutar
                  gzip
                  patchelf
                ]
              else
                [ unzip ]
            );

          text = ''
            # Injected from Nix
            ARCH="${config.arch}"
            EXT="${config.ext}"
            IS_LINUX="${if isLinux then "true" else "false"}"
            INTERPRETER="${linuxInterpreter}"
            RPATH="${linuxRuntimeLibs}"

            ${builtins.readFile ./opencode.sh}
          '';
        };

      in
      {
        packages.default = opencode-wrapper;
        apps.default = flake-utils.lib.mkApp {
          drv = opencode-wrapper;
        };
      }
    );
}
