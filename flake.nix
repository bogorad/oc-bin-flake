{
  description = "Self-updating SST OpenCode wrapper (Musl)";

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

        # Dependencies for Musl Binary
        runtimeLibs = pkgs.lib.makeLibraryPath [
          pkgs.musl
          pkgs.pkgsMusl.stdenv.cc.cc.lib
          pkgs.pkgsMusl.zlib
        ];

        interpreter = "${pkgs.musl}/lib/ld-musl-x86_64.so.1";

        opencode-wrapper = pkgs.writeShellApplication {
          name = "opencode";
          runtimeInputs = with pkgs; [
            curl
            gnutar
            gzip
            patchelf
            jq
            file
            gnugrep
          ];

          text = ''
            TARGET="/tmp/opencode"
            REPO="sst/opencode"
            ARCH="linux-x64-musl"

            # --- AUTO-UPDATE LOGIC ---

            CURRENT_VER="none"

            if [ -f "$TARGET" ]; then
              # 1. Capture output (stderr too, just in case)
              VER_OUT=$("$TARGET" --version 2>&1 || true)
              
              # 2. Robust Regex: Matches 1.0.98 OR v1.0.98
              DETECTED=$(echo "$VER_OUT" | grep -oP 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
              
              if [ -n "$DETECTED" ]; then
                CURRENT_VER="$DETECTED"
              fi
            fi

            # Fetch Latest Tag
            if LATEST_JSON=$(curl -s "https://api.github.com/repos/$REPO/releases/latest"); then
              LATEST_VER=$(echo "$LATEST_JSON" | jq -r .tag_name)
            else
              LATEST_VER="error"
            fi

            # --- NORMALIZATION FIX ---
            # Remove 'v' prefix from both versions so '1.0.98' == 'v1.0.98'
            NORM_CURRENT=''${CURRENT_VER#v}
            NORM_LATEST=''${LATEST_VER#v}

            if [ "$LATEST_VER" != "null" ] && [ "$LATEST_VER" != "error" ]; then
               # Compare the NORMALIZED versions
               if [ "$NORM_CURRENT" != "$NORM_LATEST" ]; then
                  echo "[opencode-wrapper] Update required: $CURRENT_VER -> $LATEST_VER"
                  
                  DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_VER/opencode-$ARCH.tar.gz"
                  TMP_DIR=$(mktemp -d)
                  
                  if curl -L -s --fail "$DOWNLOAD_URL" -o "$TMP_DIR/opencode.tar.gz"; then
                    tar -xzf "$TMP_DIR/opencode.tar.gz" -C "$TMP_DIR"
                    BINARY="$TMP_DIR/opencode"
                    
                    if [ -f "$BINARY" ]; then
                      patchelf --set-interpreter "${interpreter}" "$BINARY"
                      patchelf --set-rpath "${runtimeLibs}" "$BINARY"
                      mv "$BINARY" "$TARGET"
                      chmod +x "$TARGET"
                      echo "[opencode-wrapper] Updated successfully."
                    fi
                  else
                     echo "[opencode-wrapper] Update failed. Using existing binary."
                  fi
                  rm -rf "$TMP_DIR"
               fi
            fi

            # --- EXECUTION ---
            if [ ! -x "$TARGET" ]; then
              echo "Error: opencode binary not available at $TARGET"
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
