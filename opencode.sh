TARGET="/tmp/opencode"
REPO="sst/opencode"

# --- 1. VERSION CHECK ---
CURRENT_VER="none"
if [ -f "$TARGET" ]; then
  VER_OUT=$("$TARGET" --version 2>&1 || true)
  DETECTED=$(echo "$VER_OUT" | rg -oP 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
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
