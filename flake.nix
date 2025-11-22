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
            TARGET="/tmp/opencode"
            REPO="sst/opencode"

            # Injected from Nix
            ARCH="${config.arch}"
            EXT="${config.ext}"
            IS_LINUX="${if isLinux then "true" else "false"}"
            INTERPRETER="${linuxInterpreter}"
            RPATH="${linuxRuntimeLibs}"

            # --- 1. VERSION CHECK ---
            CURRENT_VER="none"
            if [ -f "$TARGET" ]; then
              VER_OUT=$("$TARGET" --version 2>&1 || true)
              DETECTED=$(echo "$VER_OUT" | grep -oP 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
              [ -n "$DETECTED" ] && CURRENT_VER="$DETECTED"
            fi

            if ! LATEST_JSON=$(curl -s --connect-timeout 5 "https://api.github.com/repos/$REPO/releases/latest"); then
              echo "Error: Failed to check for updates."
              exit 1
            fi
            LATEST_VER=$(echo "$LATEST_JSON" | jq -r .tag_name)

            # Normalize (strip 'v')
            NORM_CURRENT=''${CURRENT_VER#v}
            NORM_LATEST=''${LATEST_VER#v}

            # --- 2. UPDATE LOGIC ---
            if [ "$LATEST_VER" != "null" ] && [ "$NORM_CURRENT" != "$NORM_LATEST" ]; then
               echo "[opencode] Update needed: $CURRENT_VER -> $LATEST_VER ($ARCH)"
               
               DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_VER/opencode-$ARCH.$EXT"
               TMP_DIR=$(mktemp -d)
               
               echo "Downloading $DOWNLOAD_URL..."
               if curl -L -s --show-error --fail "$DOWNLOAD_URL" -o "$TMP_DIR/file.$EXT"; then
                 
                 # Extraction Logic (Zip vs Tar)
                 if [ "$EXT" = "zip" ]; then
                   unzip -q -o "$TMP_DIR/file.$EXT" -d "$TMP_DIR"
                 else
                   tar -xzf "$TMP_DIR/file.$EXT" -C "$TMP_DIR"
                 fi
                 
                 # Locate Binary (Darwin zips might have 'opencode' at root)
                 BINARY="$TMP_DIR/opencode"
                 
                 if [ -f "$BINARY" ]; then
                   # --- LINUX PATCHING ONLY ---
                   if [ "$IS_LINUX" = "true" ]; then
                     echo "Patching ELF..."
                     patchelf --set-interpreter "$INTERPRETER" "$BINARY"
                     patchelf --set-rpath "$RPATH" "$BINARY"
                   fi
                   
                   mv "$BINARY" "$TARGET"
                   chmod +x "$TARGET"
                   echo "[opencode] Updated successfully."
                 else
                   echo "Error: Binary not found in archive."
                   ls -la "$TMP_DIR"
                   exit 1
                 fi
               else
                  echo "[opencode] Download failed."
                  exit 1
               fi
               rm -rf "$TMP_DIR"
            fi

            # --- 3. EXECUTION ---
            if [ ! -x "$TARGET" ]; then
              echo "Error: Binary missing at $TARGET"
              exit 1
            fi
            exec "$TARGET" "$@"
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
