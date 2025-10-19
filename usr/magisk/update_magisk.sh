#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ver="$(cat "$DIR/magisk_version" 2>/dev/null || echo -n 'none')"

# --- resolve target version & download URL ---
if [ "x$1" = "xcanary" ]; then
  nver="canary"
  magisk_link="https://github.com/topjohnwu/magisk-files/raw/${nver}/app-debug.apk"
elif [ "x$1" = "xalpha" ]; then
  nver="alpha"
  magisk_link="https://github.com/vvb2060/magisk_files/raw/${nver}/app-release.apk"
else
  dash='-'
  if [ -z "$1" ]; then
    nver="$(curl -fsSL https://github.com/topjohnwu/Magisk/releases | grep -m 1 -Poe 'Magisk v[\d\.]+' | cut -d ' ' -f 2)"
  else
    nver="$1"
  fi
  [ "$nver" = "v26.3" ] && dash='.'
  magisk_link="https://github.com/topjohnwu/Magisk/releases/download/${nver}/Magisk${dash}${nver}.apk"
fi

# --- only update when needed ---
if [ \( -n "$nver" \) -a \( "$nver" != "$ver" \) -o ! \( -f "$DIR/magiskinit" \) -o \( "$nver" = "canary" \) -o \( "$nver" = "alpha" \) ]; then
  echo "Updating Magisk from $ver to $nver"

  # download .apk; fall back to .zip
  rm -f "$DIR/magisk.zip"
  if ! curl -fL --retry 3 --retry-delay 2 -o "$DIR/magisk.zip" "$magisk_link"; then
    alt="${magisk_link%.apk}.zip"
    curl -fL --retry 3 --retry-delay 2 -o "$DIR/magisk.zip" "$alt"
  fi

  # --- begin robust Magisk extract ---
  contents="$(unzip -Z1 "$DIR/magisk.zip" 2>/dev/null || true)"
  if [ -z "$contents" ] && command -v zipinfo >/dev/null 2>&1; then
    contents="$(zipinfo -1 "$DIR/magisk.zip" 2>/dev/null || true)"
  fi

  have() { grep -Fxq "$1" <<<"$contents"; }

  # Clean old temp folders if any
  rm -rf "$DIR/arm" "$DIR/lib" "$DIR/assets" || true

  # Legacy layout: single arm/magiskinit64
  if have "arm/magiskinit64"; then
    unzip -o "$DIR/magisk.zip" "arm/magiskinit64" -d "$DIR" >/dev/null
    mv -f "$DIR/arm/magiskinit64" "$DIR/magiskinit"
    : > "$DIR/magisk32.xz"
    : > "$DIR/magisk64.xz"
  else
    # Build the list of files that actually exist
    to_extract=()
    have "lib/arm64-v8a/libmagiskinit.so" && to_extract+=("lib/arm64-v8a/libmagiskinit.so")
    have "lib/armeabi-v7a/libmagiskinit.so" && to_extract+=("lib/armeabi-v7a/libmagiskinit.so")
    have "lib/armeabi-v7a/libmagisk32.so"   && to_extract+=("lib/armeabi-v7a/libmagisk32.so")
    have "lib/arm64-v8a/libmagisk64.so"     && to_extract+=("lib/arm64-v8a/libmagisk64.so")
    have "assets/stub.apk"                   && to_extract+=("assets/stub.apk")

    if [ ${#to_extract[@]} -gt 0 ]; then
      unzip -o "$DIR/magisk.zip" "${to_extract[@]}" -d "$DIR" >/dev/null
    fi

    # Choose magiskinit: prefer arm64, else armeabi-v7a
    if [ -f "$DIR/lib/arm64-v8a/libmagiskinit.so" ]; then
      mv -f "$DIR/lib/arm64-v8a/libmagiskinit.so" "$DIR/magiskinit"
    elif [ -f "$DIR/lib/armeabi-v7a/libmagiskinit.so" ]; then
      mv -f "$DIR/lib/armeabi-v7a/libmagiskinit.so" "$DIR/magiskinit"
    else
      echo "ERROR: magiskinit not found in archive (looked for arm64-v8a/armeabi-v7a)." >&2
      exit 2
    fi

    # Optional libs
    if [ -f "$DIR/lib/armeabi-v7a/libmagisk32.so" ]; then
      mv -f "$DIR/lib/armeabi-v7a/libmagisk32.so" "$DIR/magisk32"
      xz --force --check=crc32 "$DIR/magisk32"
    fi
    if [ -f "$DIR/lib/arm64-v8a/libmagisk64.so" ]; then
      mv -f "$DIR/lib/arm64-v8a/libmagisk64.so" "$DIR/magisk64"
      xz --force --check=crc32 "$DIR/magisk64"
    fi
    if [ -f "$DIR/assets/stub.apk" ]; then
      mv -f "$DIR/assets/stub.apk" "$DIR/stub"
      xz --force --check=crc32 "$DIR/stub"
    fi

    # Placeholders if toolchain expects them
    [ -f "$DIR/magisk32.xz" ] || : > "$DIR/magisk32.xz"
    [ -f "$DIR/magisk64.xz" ] || : > "$DIR/magisk64.xz"
  fi
  # --- end robust Magisk extract ---

  echo -n "$nver" > "$DIR/magisk_version"
  rm -f "$DIR/magisk.zip"
  touch "$DIR/initramfs_list"
else
  echo "Nothing to be done: Magisk version $nver"
fi
