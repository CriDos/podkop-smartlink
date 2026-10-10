#!/bin/sh
# podkop-engine installer for OpenWrt.
#
# Usage (interactive menu):
#   sh <(wget -qO- https://raw.githubusercontent.com/CriDos/podkop-smartlink/main/_install-singbox.sh)
#
# Non-interactive (installs the pinned recommended version; the menu is shown
# only when stdin is a TTY):
#   sh _install-singbox.sh
#   VERSION=1.14.2-r13 sh _install-singbox.sh
#
# podkop-engine is FiyeroT's patched sing-box build for podkop (xhttp
# transport, tools.decode-link, urltest fallbacks, memory failsafes):
# https://github.com/FiyeroT/podkop-engine
# An old engine package (sing-box, sing-box-extended, ...) must be removed
# first: opkg remove --force-depends <name> / apk del <name>.

[ -f /etc/openwrt_release ] || { echo "Error: this is not OpenWrt."; exit 1; }
. /etc/openwrt_release

SERVICE_STOPPED=0
MIRROR_PREFIX="https://ghproxy.net/"
WORK_DIR="/tmp/engine-install"
PDK_REPO="FiyeroT/podkop-engine"
RECOMMENDED_PDK="1.14.2-r13"
DEST_FILE="/usr/bin/sing-box"
TMP_NEED_KB=25000
ROOT_NEED_KB=26000

R=""; G=""; Y=""; N=""
if [ -t 1 ]; then
    R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; N="\033[0m"
fi
say()  { printf "$G[*]${N} %s\n" "$1"; }
warn() { printf "$Y[!]${N} %s\n" "$1"; }
die()  { printf "$R[x]${N} %s\n" "$1"; rm -rf "$WORK_DIR"; exit 1; }
free_kb() { df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}'; }

PKG=""
PKG_EXT=""
if command -v apk >/dev/null 2>&1; then
    PKG="apk"; PKG_EXT="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG="opkg"; PKG_EXT="ipk"
else
    die "Neither apk nor opkg found."
fi

fetch() { # stdout
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -k --connect-timeout 10 "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --no-check-certificate --timeout=10 "$1"
    else
        uclient-fetch -qO- --no-check-certificate --timeout=10 "$1"
    fi
}
download() { # $1 url, $2 file
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -k --connect-timeout 30 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate --timeout=30 -O "$2" "$1"
    else
        uclient-fetch -q --no-check-certificate --timeout=30 -O "$2" "$1"
    fi
}

# Latest stable podkop-engine tag (without the leading v), prereleases
# filtered out.
github_latest_pdk() {
    local releases
    releases=$(fetch "https://api.github.com/repos/$PDK_REPO/releases?per_page=30" 2>/dev/null) || return 1
    [ -n "$releases" ] || return 1
    if command -v jsonfilter >/dev/null 2>&1; then
        printf '%s' "$releases" | jsonfilter -e '@[*].tag_name' 2>/dev/null | grep -viE 'rc|beta|alpha' | head -n 1 | sed 's/^v//'
    else
        printf '%s' "$releases" | grep '"tag_name"' | awk -F'"' '{print $4}' | grep -viE 'rc|beta|alpha' | head -n 1 | sed 's/^v//'
    fi
}

VERSION="${VERSION:-}"
if [ -z "$VERSION" ] && [ -t 0 ]; then
    say "Querying GitHub for the latest releases..."
    pdk_latest=$(github_latest_pdk 2>/dev/null || true)
    [ -n "$pdk_latest" ] || pdk_latest="unavailable"

    printf '\nSelect what to install:\n'
    printf '  1) podkop-engine %s (recommended)\n' "$RECOMMENDED_PDK"
    printf '  2) podkop-engine latest stable (%s)\n' "$pdk_latest"
    printf 'Choice [1]: '
    read -r choice || choice=""
    case "$choice" in
        2) VERSION="$pdk_latest" ;;
        *) VERSION="$RECOMMENDED_PDK" ;;
    esac
    if [ "$VERSION" = "unavailable" ]; then
        warn "GitHub API unavailable, falling back to pinned version $RECOMMENDED_PDK."
        VERSION="$RECOMMENDED_PDK"
    fi
fi
[ -n "$VERSION" ] || VERSION="$RECOMMENDED_PDK"

ASSET="podkop-engine_${VERSION}_openwrt_${DISTRIB_ARCH}.${PKG_EXT}"
BASE_URL="https://github.com/$PDK_REPO/releases/download/v$VERSION"
URL="$BASE_URL/$ASSET"
say "Engine: podkop-engine, version: $VERSION, asset: $ASSET"

TMP_FREE=$(free_kb /tmp)
[ -z "$TMP_FREE" ] && TMP_FREE=0
if [ "$TMP_FREE" -lt "$TMP_NEED_KB" ]; then
    ROOT_FREE=$(free_kb /root)
    [ -z "$ROOT_FREE" ] && ROOT_FREE=0
    if [ "$ROOT_FREE" -ge "$TMP_NEED_KB" ]; then
        WORK_DIR="/root/engine-install"
        warn "Low space in /tmp, using $WORK_DIR."
    else
        die "Not enough free space (need ~$(( TMP_NEED_KB / 1024 )) MB in /tmp or /root)."
    fi
fi
rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR" || die "Failed to create $WORK_DIR."
trap '[ "$SERVICE_STOPPED" = "1" ] && [ -n "$SERVICE" ] && "/etc/init.d/$SERVICE" start >/dev/null 2>&1; rm -rf "$WORK_DIR"' EXIT INT TERM

say "Downloading..."
if ! download "$URL" "$WORK_DIR/$ASSET"; then
    warn "Direct download failed, trying mirror $MIRROR_PREFIX..."
    download "${MIRROR_PREFIX}${URL}" "$WORK_DIR/$ASSET" || die "Download failed both directly and via the mirror."
fi
[ -s "$WORK_DIR/$ASSET" ] || die "Downloaded file is empty."

say "Verifying sha256..."
SUMS=$(fetch "$BASE_URL/SHA256SUMS" 2>/dev/null || true)
EXPECTED=$(printf '%s\n' "$SUMS" | awk -v f="$ASSET" '$2 == f {print $1}' | head -n 1)
if [ -n "$SUMS" ] && [ -z "$EXPECTED" ]; then
    die "No $ASSET in SHA256SUMS - no podkop-engine build for $DISTRIB_ARCH."
fi
if [ -n "$EXPECTED" ] && command -v sha256sum >/dev/null 2>&1; then
    ACTUAL=$(sha256sum "$WORK_DIR/$ASSET" | awk '{print $1}')
    [ "$EXPECTED" = "$ACTUAL" ] || die "sha256 mismatch: expected $EXPECTED, got $ACTUAL."
    say "sha256 OK."
elif [ -z "$SUMS" ]; then
    warn "SHA256SUMS unavailable - skipping verification."
else
    warn "sha256sum missing - skipping verification."
fi

if [ -f "$DEST_FILE" ]; then
    OLD_VER=$("$DEST_FILE" version 2>/dev/null | head -n 1)
    say "Current binary: ${OLD_VER:-unknown}"
fi

# Pre-flight: the destination filesystem must hold the new binary (~22.5 MB)
# plus a small margin, counting the space the old binary frees. Checked
# before the service is stopped so a full disk cannot leave the router
# without a running engine.
DEST_OLD_KB=0
if [ -f "$DEST_FILE" ]; then
    DEST_OLD_BYTES=$(wc -c < "$DEST_FILE" 2>/dev/null || echo 0)
    DEST_OLD_KB=$(( DEST_OLD_BYTES / 1024 ))
fi
DEST_FREE_KB=$(free_kb "$(dirname "$DEST_FILE")")
[ -z "$DEST_FREE_KB" ] && DEST_FREE_KB=0
AVAIL_KB=$(( DEST_FREE_KB + DEST_OLD_KB ))
if [ "$AVAIL_KB" -lt "$ROOT_NEED_KB" ]; then
    die "Not enough space in $(dirname "$DEST_FILE"): need ~$(( ROOT_NEED_KB / 1024 )) MB, available ~$(( AVAIL_KB / 1024 )) MB (free $(( DEST_FREE_KB / 1024 )) MB + old binary $(( DEST_OLD_KB / 1024 )) MB)."
fi

if [ "${SERVICE-unset}" = "unset" ]; then
    if [ -f /etc/init.d/podkop ]; then SERVICE="podkop"
    elif [ -f /etc/init.d/sing-box ]; then SERVICE="sing-box"
    else SERVICE=""; fi
fi
if [ -n "$SERVICE" ] && [ -x "/etc/init.d/$SERVICE" ]; then
    say "Stopping $SERVICE..."
    "/etc/init.d/$SERVICE" stop >/dev/null 2>&1
    killall sing-box >/dev/null 2>&1
    sleep 2
    SERVICE_STOPPED=1
fi

# The package managers check free space without knowing the old raw binary
# will be replaced, so remove it up front.
rm -f "$DEST_FILE"

say "Installing the podkop-engine package..."
if [ "$PKG" = "apk" ]; then
    apk add --allow-untrusted --force-reinstall "$WORK_DIR/$ASSET" || die "apk add failed - an old engine package may still be installed (apk del <name>)."
else
    opkg install --force-reinstall "$WORK_DIR/$ASSET" || die "opkg install failed - an old engine package may still be installed (opkg remove --force-depends <name>), or /overlay is out of space."
fi

# EikeiDev UPX variant leftovers: the real binary lives elsewhere and this
# path is only a wrapper.
rm -f /usr/libexec/sing-box-core /etc/sing-box-version.cache

INSTALLED=$("$DEST_FILE" version 2>/dev/null | head -n 1)
say "Installed: ${INSTALLED:-failed to get the version}"
if ! "$DEST_FILE" version 2>/dev/null | grep -q "tools.decode-link"; then
    warn "The installed engine does not report tools.decode-link - xhttp links will not work with podkop."
fi

if [ -n "$SERVICE" ] && [ -x "/etc/init.d/$SERVICE" ]; then
    say "Starting $SERVICE..."
    if "/etc/init.d/$SERVICE" start >/dev/null 2>&1; then
        SERVICE_STOPPED=0
    else
        warn "Failed to start $SERVICE, check the logs."
    fi
fi

# Pick up the new engine capabilities in the SmartLink daemon (xhttp support
# is detected once per process).
if [ -x /etc/init.d/podkop-smartlink ]; then
    /etc/init.d/podkop-smartlink restart >/dev/null 2>&1
fi
say "Done."
