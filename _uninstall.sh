#!/bin/sh
# Uninstallation script for podkop-smartlink.
# Removes all installed files and stops the service.
# Must be run ON THE ROUTER as root.

set -e

STATE_DIR="/tmp/podkop-smartlink"
STATE_LINKS_FULL="$STATE_DIR/links.full"
STATE_LINKS_EXCLUDED="$STATE_DIR/links.excluded"
STATE_LINKS_CACHE="$STATE_DIR/links.cache"
STATE_SUB_CACHE="$STATE_DIR/sub_cache"
TAB="$(printf '\t')"

echo "=========================================="
echo "Uninstall: podkop-smartlink"
echo "=========================================="

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run as root"
  exit 1
fi

uci_escape() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

clear_smartlink_backup() {
  uci -q delete podkop-smartlink.main.managed_section 2>/dev/null || true
  uci -q delete podkop-smartlink.main.backup_proxy_config_type 2>/dev/null || true
  uci -q delete podkop-smartlink.main.backup_selector_proxy_links 2>/dev/null || true
  uci -q commit podkop-smartlink 2>/dev/null || true
}

state_urls() {
  local file="$1"
  [ -s "$file" ] || return 1
  if grep -q "$TAB" "$file" 2>/dev/null; then
    cut -f1 "$file" 2>/dev/null
  else
    cat "$file" 2>/dev/null
  fi
}

known_smartlink_urls() {
  local file
  for file in "$STATE_LINKS_FULL" "$STATE_LINKS_EXCLUDED" "$STATE_LINKS_CACHE"; do
    [ -s "$file" ] || continue
    state_urls "$file"
  done
  for file in "$STATE_SUB_CACHE"/sub_*; do
    [ -s "$file" ] || continue
    cut -f1 "$file" 2>/dev/null
  done
}

same_url_set() {
  [ "$(printf '%s\n' "$1" | sort -u)" = "$(printf '%s\n' "$2" | sort -u)" ]
}

backup_matches_known_state() {
  local old_type old_links known
  old_type="$(uci -q get podkop-smartlink.main.backup_proxy_config_type 2>/dev/null || true)"
  [ "$old_type" = "selector" ] || return 1
  old_links="$(uci -q get podkop-smartlink.main.backup_selector_proxy_links 2>/dev/null | tr ' ' '\n' | grep '://' || true)"
  [ -n "$old_links" ] || return 1
  known="$(known_smartlink_urls | grep '://' | sort -u || true)"
  [ -n "$known" ] || return 1
  same_url_set "$old_links" "$known"
}

sanitize_legacy_backup() {
  local managed="$1"
  [ -n "$managed" ] || return 1
  [ "$(uci -q get podkop-smartlink.main.managed_section 2>/dev/null || true)" = "$managed" ] || return 1
  backup_matches_known_state || return 1
  uci -q delete podkop-smartlink.main.backup_proxy_config_type 2>/dev/null || true
  uci -q delete podkop-smartlink.main.backup_selector_proxy_links 2>/dev/null || true
  uci -q commit podkop-smartlink 2>/dev/null || return 1
  echo "Detected legacy SmartLink selector snapshot; clearing backup before restore"
  return 0
}

restore_managed_section() {
  local managed="$1" batch old_type old_links url old_type_esc url_esc
  [ -n "$managed" ] || return 0

  sanitize_legacy_backup "$managed" || true

  batch="/tmp/podkop-smartlink-uninstall-uci.$$"
  old_type="$(uci -q get podkop-smartlink.main.backup_proxy_config_type 2>/dev/null || true)"
  old_links="$(uci -q get podkop-smartlink.main.backup_selector_proxy_links 2>/dev/null || true)"

  uci -q delete "podkop.$managed.selector_proxy_links" 2>/dev/null || true
  if [ -z "$old_type" ]; then
    uci -q delete "podkop.$managed.proxy_config_type" 2>/dev/null || true
  fi

  {
    if [ -n "$old_type" ]; then
      old_type_esc="$(uci_escape "$old_type")"
      printf "set podkop.%s.proxy_config_type='%s'\n" "$managed" "$old_type_esc"
    fi
    printf '%s' "$old_links" | tr ' ' '\n' | while IFS= read -r url; do
      [ -n "$url" ] || continue
      url_esc="$(uci_escape "$url")"
      printf "add_list podkop.%s.selector_proxy_links='%s'\n" "$managed" "$url_esc"
    done
  } > "$batch"

  if uci -q batch < "$batch" 2>/dev/null && uci -q commit podkop 2>/dev/null; then
    rm -f "$batch"
    clear_smartlink_backup
    /etc/init.d/podkop reload >/dev/null 2>&1 || true
    return 0
  fi

  rm -f "$batch"
  uci -q revert podkop 2>/dev/null || true
  return 1
}

cleanup_legacy_section() {
  local target ptype plinks
  target="$(uci -q get podkop-smartlink.main.target_section 2>/dev/null || true)"
  [ -n "$target" ] || target="main"
  ptype="$(uci -q get "podkop.$target.proxy_config_type" 2>/dev/null || true)"
  plinks="$(uci -q get "podkop.$target.selector_proxy_links" 2>/dev/null || true)"

  [ "$ptype" = "selector" ] || [ -n "$plinks" ] || return 0

  uci -q delete "podkop.$target.selector_proxy_links" 2>/dev/null || true
  if [ "$ptype" = "selector" ]; then
    uci -q delete "podkop.$target.proxy_config_type" 2>/dev/null || true
  fi
  uci -q commit podkop 2>/dev/null || {
    uci -q revert podkop 2>/dev/null || true
    return 1
  }
  /etc/init.d/podkop reload >/dev/null 2>&1 || true
  return 0
}

# Stop and disable the service
echo "Stopping service..."
/etc/init.d/podkop-smartlink stop >/dev/null 2>&1 || true
/etc/init.d/podkop-smartlink disable >/dev/null 2>&1 || true
/usr/bin/podkop-smartlink stop >/dev/null 2>&1 || true

# Restore only the Podkop section previously managed by SmartLink.
echo "Restoring Podkop UCI..."
managed="$(uci -q get podkop-smartlink.main.managed_section 2>/dev/null || true)"
if [ -n "$managed" ]; then
  if ! restore_managed_section "$managed"; then
    echo "Error: failed to restore Podkop section '$managed'; SmartLink files were not removed"
    exit 1
  fi
else
  if ! cleanup_legacy_section; then
    echo "Error: failed to clean legacy Podkop SmartLink section; SmartLink files were not removed"
    exit 1
  fi
fi

# ---- backend ----
echo "Removing backend files..."
rm -f /usr/bin/podkop-smartlink
rm -f /usr/bin/podkop-smartlink-read
rm -f /usr/bin/podkop-smartlink-write
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
