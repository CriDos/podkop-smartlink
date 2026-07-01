#!/bin/sh
# Uninstallation script for podkop-smartlink.
# Removes all installed files and stops the service.
# Must be run ON THE ROUTER as root.

set -e

echo "=========================================="
echo "Uninstall: podkop-smartlink"
echo "=========================================="

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run as root"
  exit 1
fi

# Stop and disable the service
echo "Stopping service..."
/etc/init.d/podkop-smartlink stop >/dev/null 2>&1 || true
/etc/init.d/podkop-smartlink disable >/dev/null 2>&1 || true
/usr/bin/podkop-smartlink stop >/dev/null 2>&1 || true

# Clean up Podkop UCI: remove selector_proxy_links and reset proxy_config_type
echo "Cleaning Podkop UCI..."
for section in $(uci -q show podkop 2>/dev/null | grep 'proxy_config_type=selector' | cut -d. -f2 | cut -d= -f1); do
  uci -q delete "podkop.$section.selector_proxy_links" 2>/dev/null || true
  uci -q set "podkop.$section.proxy_config_type=" 2>/dev/null || true
done || true
uci -q commit podkop 2>/dev/null || true
/etc/init.d/podkop reload >/dev/null 2>&1 || true

# ---- backend ----
echo "Removing backend files..."
rm -f /usr/bin/podkop-smartlink
rm -f /etc/init.d/podkop-smartlink
rm -rf /usr/lib/podkop-smartlink

# ---- LuCI ----
echo "Removing LuCI files..."
rm -f /www/luci-static/resources/view/podkop/smartlink.js
rm -f /usr/share/luci/menu.d/luci-app-podkop-smartlink.json
rm -f /usr/share/rpcd/acl.d/luci-app-podkop-smartlink.json

# ---- state ----
echo "Removing state..."
rm -rf /tmp/podkop-smartlink

# Refresh rpcd
/etc/init.d/rpcd reload >/dev/null 2>&1 || true
rm -f /tmp/luci-indexcache* /var/luci-indexcache* 2>/dev/null || true

echo ""
echo "=========================================="
echo "Uninstalled successfully"
echo "=========================================="
echo ""
echo "Note: /etc/config/podkop-smartlink was kept (user settings)."
echo "To remove it too: rm -f /etc/config/podkop-smartlink"
