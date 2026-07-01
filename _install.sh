#!/bin/sh
# Installation script for podkop-smartlink.
# Downloads and installs backend + LuCI files onto a running OpenWrt router.
# Must be run ON THE ROUTER as root.

set -e

REPO="https://github.com/CriDos/podkop-smartlink/raw/main"
TMP="/tmp/podkop-smartlink-install"

echo "=========================================="
echo "Install: podkop-smartlink"
echo "=========================================="

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run as root"
  exit 1
fi

if ! command -v uci >/dev/null 2>&1; then
  echo "Error: not an OpenWrt system (uci not found)"
  exit 1
fi

if ! opkg list-installed 2>/dev/null | grep -qE "^(podkop|luci-app-podkop) " \
   && ! apk info 2>/dev/null | grep -qE "^(podkop|luci-app-podkop)$"; then
  echo "Error: Podkop is not installed"
  echo "Install first: opkg install podkop  (or)  apk add podkop"
  exit 1
fi

# Check required runtime deps
for dep in curl wget jq base64; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Installing $dep ..."
    if command -v opkg >/dev/null 2>&1; then
      opkg update >/dev/null 2>&1 || true
      opkg install "$dep" >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
      apk add "$dep" >/dev/null 2>&1 || true
    fi
  fi
done

rm -rf "$TMP"
mkdir -p "$TMP/lib" "$TMP/luci"

echo "Downloading files..."

# Download helper: verifies file is non-empty
dl() {
  local url="$1" dest="$2"
  wget -q --no-check-certificate -O "$dest" "$url" || true
  if [ ! -s "$dest" ]; then
    echo "Error: failed to download $url"
    rm -rf "$TMP"
    exit 1
  fi
}

# Backend libraries
for f in constants.sh logging.sh utils.sh config.sh subscription.sh \
         clash_api.sh history.sh status.sh selector.sh daemon.sh; do
  dl "$REPO/files/usr/lib/podkop-smartlink/$f" "$TMP/lib/$f"
done

# Backend CLI + init.d + config + uci-defaults
dl "$REPO/files/usr/bin/podkop-smartlink" "$TMP/podkop-smartlink"
dl "$REPO/files/etc/init.d/podkop-smartlink" "$TMP/podkop-smartlink.init"
dl "$REPO/files/etc/config/podkop-smartlink" "$TMP/podkop-smartlink.config"
dl "$REPO/luci-app-podkop-smartlink/root/etc/uci-defaults/50_luci-podkop-smartlink" "$TMP/50_luci-podkop-smartlink"

# LuCI
dl "$REPO/luci-app-podkop-smartlink/htdocs/luci-static/resources/view/podkop/smartlink.js" "$TMP/luci/smartlink.js"
dl "$REPO/luci-app-podkop-smartlink/root/usr/share/luci/menu.d/luci-app-podkop-smartlink.json" "$TMP/luci/menu.json"
dl "$REPO/luci-app-podkop-smartlink/root/usr/share/rpcd/acl.d/luci-app-podkop-smartlink.json" "$TMP/luci/acl.json"

# ---- install backend ----
echo "Installing backend..."

mkdir -p /usr/lib/podkop-smartlink
cp "$TMP/lib/"*.sh /usr/lib/podkop-smartlink/
chmod 644 /usr/lib/podkop-smartlink/*.sh

cp "$TMP/podkop-smartlink" /usr/bin/podkop-smartlink
chmod +x /usr/bin/podkop-smartlink

cp "$TMP/podkop-smartlink.init" /etc/init.d/podkop-smartlink
chmod +x /etc/init.d/podkop-smartlink

if [ ! -f /etc/config/podkop-smartlink ]; then
  cp "$TMP/podkop-smartlink.config" /etc/config/podkop-smartlink
  chmod 644 /etc/config/podkop-smartlink
  echo "Created default config /etc/config/podkop-smartlink"
fi

# ---- install LuCI ----
echo "Installing LuCI..."

mkdir -p /www/luci-static/resources/view/podkop
cp "$TMP/luci/smartlink.js" /www/luci-static/resources/view/podkop/smartlink.js
chmod 644 /www/luci-static/resources/view/podkop/smartlink.js

mkdir -p /usr/share/luci/menu.d
cp "$TMP/luci/menu.json" /usr/share/luci/menu.d/luci-app-podkop-smartlink.json
chmod 644 /usr/share/luci/menu.d/luci-app-podkop-smartlink.json

mkdir -p /usr/share/rpcd/acl.d
cp "$TMP/luci/acl.json" /usr/share/rpcd/acl.d/luci-app-podkop-smartlink.json
chmod 644 /usr/share/rpcd/acl.d/luci-app-podkop-smartlink.json

# Run uci-defaults (clears LuCI cache, reloads rpcd)
if [ -f "$TMP/50_luci-podkop-smartlink" ]; then
  sh "$TMP/50_luci-podkop-smartlink" >/dev/null 2>&1 || true
fi

# Enable service
/etc/init.d/podkop-smartlink enable >/dev/null 2>&1 || true

# Restart daemon if already running (reinstall case)
if [ -f /var/run/podkop-smartlink.pid ] 2>/dev/null; then
  echo "Restarting daemon (reinstall)..."
  /etc/init.d/podkop-smartlink restart >/dev/null 2>&1 || true
fi

rm -rf "$TMP"

echo ""
echo "=========================================="
echo "Installed successfully"
echo "=========================================="
echo ""
echo "LuCI: Services -> Podkop SmartLink"
