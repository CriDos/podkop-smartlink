#!/bin/sh
# Engine installer for OpenWrt: podkop-engine (recommended) or the original
# sing-box (upstream SagerNet).
#
# Usage (interactive menu):
#   sh <(wget -qO- https://raw.githubusercontent.com/CriDos/podkop-smartlink/main/_install-singbox.sh)
#
# Non-interactive (the menu is shown only when stdin is a TTY):
#   ENGINE=pdk|pdkfull|upstream sh _install-singbox.sh
#
# Environment overrides:
#   ENGINE=pdk|pdkfull|upstream  engine to install: pinned stable (skips the menu)
#   VERSION=<ver>                explicit version (skips the GitHub query)
#   MENU=1|0                     force/disable the menu (0 also useful for cron)
#   DEST_FILE=/usr/bin/sing-box  target path (upstream binary replace only)
#   SERVICE=podkop               service to stop/start (default: auto-detect podkop/sing-box, empty = skip)
#
# podkop-engine is FiyeroT's patched sing-box build for podkop (xhttp
# transport, tools.decode-link, urltest fallbacks, memory failsafes):
# https://github.com/FiyeroT/podkop-engine
# It ships as an OpenWrt package (.apk on 25.12+, .ipk on 24.10 and older) and
# is installed through the package manager; a stock sing-box package present
# in the database is removed first (podkop-engine provides sing-box).
# Upstream sing-box releases (raw binary replace):
# https://github.com/SagerNet/sing-box

[ -f /etc/openwrt_release ] || { echo "Error: this is not OpenWrt."; exit 1; }
. /etc/openwrt_release

DEST_FILE="${DEST_FILE:-/usr/bin/sing-box}"
ENGINE="${ENGINE:-}"
SERVICE_STOPPED=0
MIRROR_PREFIX="https://ghproxy.net/"
WORK_DIR="/tmp/engine-install"
PDK_REPO="FiyeroT/podkop-engine"
UP_REPO="SagerNet/sing-box"
RECOMMENDED_PDK="1.14.2-r13"
RECOMMENDED_UP="1.14.2"
ROOT_NEED_KB=40000

R=""; G=""; Y=""; N=""
if [ -t 1 ]; then
    R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; N="\033[0m"
fi
say()  { printf "$G[*]${N} %s\n" "$1"; }
warn() { printf "$Y[!]${N} %s\n" "$1"; }
die()  { printf "$R[x]${N} %s\n" "$1"; rm -f "${DEST_FILE}.tmp"; rm -rf "$WORK_DIR"; exit 1; }

PKG=""
PKG_EXT=""
if command -v apk >/dev/null 2>&1; then
    PKG="apk"; PKG_EXT="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG="opkg"; PKG_EXT="ipk"
fi

# Only the upstream tarball needs an arch mapping; podkop-engine assets use
# the OpenWrt pkgarch ($DISTRIB_ARCH) verbatim.
UP_ARCH=""
case "$DISTRIB_ARCH" in
    aarch64*)                              UP_ARCH="arm64-musl" ;;
    arm_cortex-a7*|arm_cortex-a9*|arm_cortex-a15*) UP_ARCH="armv7-musl" ;;
    x86_64)                                UP_ARCH="amd64-musl" ;;
    mipsel_24kc|mipsel_*)                  UP_ARCH="mipsle-softfloat-musl" ;;
    mips_24kc|mips_*)                      UP_ARCH="mips-softfloat-musl" ;;
esac

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

# Latest stable upstream sing-box tag (without the leading v).
github_latest_upstream() {
    local rel ver
    rel=$(fetch "https://api.github.com/repos/$UP_REPO/releases/latest" 2>/dev/null) || return 1
    [ -n "$rel" ] || return 1
    ver=$(printf '%s' "$rel" | grep '"tag_name"' | awk -F'"' '{print $4}' | head -n 1)
    [ -n "$ver" ] || return 1
    printf '%s' "$ver" | sed 's/^v//'
}

choose_interactively() {
    local pdk_latest up_latest choice
    say "Querying GitHub for the latest releases..."
    pdk_latest=$(github_latest_pdk 2>/dev/null || true)
    up_latest=$(github_latest_upstream 2>/dev/null || true)
    [ -n "$pdk_latest" ] || pdk_latest="unavailable"
    [ -n "$up_latest" ] || up_latest="unavailable"

    printf '\nSelect what to install:\n'
    printf '  1) podkop-engine %s (recommended)\n' "$RECOMMENDED_PDK"
    printf '  2) podkop-engine latest stable (%s)\n' "$pdk_latest"
    printf '  3) podkop-engine-full latest stable (%s)\n' "$pdk_latest"
    printf '  4) sing-box (original) latest stable (%s)\n' "$up_latest"
    printf 'Choice [1]: '
    read -r choice || choice=""
    case "$choice" in
        2) ENGINE="pdk"; VERSION="$pdk_latest" ;;
        3) ENGINE="pdkfull"; VERSION="$pdk_latest" ;;
        4) ENGINE="upstream"; VERSION="$up_latest" ;;
        *) ENGINE="pdk"; VERSION="$RECOMMENDED_PDK" ;;
    esac
    if [ "$VERSION" = "unavailable" ]; then
        case "$ENGINE" in
            pdk)
                warn "GitHub API unavailable, falling back to pinned version $RECOMMENDED_PDK."
                VERSION="$RECOMMENDED_PDK" ;;
            *) die "No usable version selected." ;;
        esac
    fi
}

menu_enabled=0
if [ "${MENU-}" = "1" ]; then
    menu_enabled=1
elif [ "${MENU-}" = "0" ]; then
    menu_enabled=0
elif [ -t 0 ]; then
    menu_enabled=1
fi

if [ -z "$ENGINE" ] && [ "$menu_enabled" = "1" ]; then
    choose_interactively
fi

[ -n "$ENGINE" ] || ENGINE="pdk"

if [ -z "$VERSION" ]; then
    case "$ENGINE" in
        pdk)
            VERSION=$(github_latest_pdk 2>/dev/null || true)
            if [ -z "$VERSION" ]; then
                warn "GitHub API unavailable, falling back to pinned version $RECOMMENDED_PDK."
                VERSION="$RECOMMENDED_PDK"
            fi
            ;;
        pdkfull)
            VERSION=$(github_latest_pdk 2>/dev/null || true)
            [ -n "$VERSION" ] || die "GitHub API unavailable, cannot resolve the podkop-engine-full version."
            ;;
        upstream)
            VERSION=$(github_latest_upstream 2>/dev/null || true)
            if [ -z "$VERSION" ]; then
                warn "GitHub API unavailable, falling back to pinned version $RECOMMENDED_UP."
                VERSION="$RECOMMENDED_UP"
            fi
            ;;
        *) die "Unknown ENGINE '$ENGINE' (expected pdk, pdkfull or upstream)." ;;
    esac
fi

case "$ENGINE" in
    pdk|pdkfull)
        [ -n "$PKG" ] || die "Neither apk nor opkg found; cannot install the podkop-engine package."
        DEST_FILE="/usr/bin/sing-box" # the package owns this path
        PKG_NAME="podkop-engine"
        [ "$ENGINE" = "pdkfull" ] && PKG_NAME="podkop-engine-full"
        ASSET="${PKG_NAME}_${VERSION}_openwrt_${DISTRIB_ARCH}.${PKG_EXT}"
        ;;
    upstream)
        [ -n "$UP_ARCH" ] || die "Architecture $DISTRIB_ARCH has no upstream sing-box build."
        ASSET="sing-box-$VERSION-linux-$UP_ARCH.tar.gz"
        ;;
    *) die "Unknown ENGINE '$ENGINE' (expected pdk, pdkfull or upstream)." ;;
esac
REPO="$PDK_REPO"
[ "$ENGINE" = "upstream" ] && REPO="$UP_REPO"
BASE_URL="https://github.com/$REPO/releases/download/v$VERSION"
URL="$BASE_URL/$ASSET"
say "Engine: $ENGINE, version: $VERSION, asset: $ASSET"

TMP_NEED_KB=25000
[ "$ENGINE" = "upstream" ] && TMP_NEED_KB=130000
TMP_FREE=$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')
[ -z "$TMP_FREE" ] && TMP_FREE=0
if [ "$TMP_FREE" -lt "$TMP_NEED_KB" ]; then
    ROOT_FREE=$(df -Pk /root 2>/dev/null | awk 'NR==2 {print $4}')
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

if [ "$ENGINE" = "upstream" ]; then
    say "Verifying sha256..."
    SUMS=$(fetch "$BASE_URL/SHA256SUMS" 2>/dev/null || true)
    EXPECTED=$(printf '%s\n' "$SUMS" | awk -v f="$ASSET" '$2 == f {print $1}' | head -n 1)
    if [ -n "$EXPECTED" ] && command -v sha256sum >/dev/null 2>&1; then
        ACTUAL=$(sha256sum "$WORK_DIR/$ASSET" | awk '{print $1}')
        [ "$EXPECTED" = "$ACTUAL" ] || die "sha256 mismatch: expected $EXPECTED, got $ACTUAL."
        say "sha256 OK."
    elif command -v sha256sum >/dev/null 2>&1; then
        ACTUAL=$(sha256sum "$WORK_DIR/$ASSET" | awk '{print $1}')
        warn "No official checksums published; downloaded archive sha256: $ACTUAL"
    else
        warn "sha256sum missing - skipping verification."
    fi

    say "Extracting..."
    tar -xzf "$WORK_DIR/$ASSET" -C "$WORK_DIR" || die "Failed to extract the archive."
    BIN=$(find "$WORK_DIR" -type f -name sing-box | head -n 1)
    [ -n "$BIN" ] || die "sing-box binary not found in the archive."
    rm -f "$WORK_DIR/$ASSET"
    NEW_VER=$("$BIN" version 2>/dev/null | head -n 1)
    [ -n "$NEW_VER" ] || die "The downloaded binary does not run on this system."
    BIN_BYTES=$(wc -c < "$BIN")
else
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
fi

if [ -f "$DEST_FILE" ]; then
    OLD_VER=$("$DEST_FILE" version 2>/dev/null | head -n 1)
    say "Current binary: ${OLD_VER:-unknown}"
fi

# Pre-flight: the destination filesystem must hold the new binary plus a
# small margin, counting the space the old binary frees (measured before the
# service is stopped so a full disk cannot leave the router without a running
# engine). For upstream the size is the extracted binary; for podkop-engine a
# fixed estimate (the package size varies by arch).
DEST_DIR=$(dirname "$DEST_FILE")
mkdir -p "$DEST_DIR" 2>/dev/null || true
DEST_OLD_KB=0
if [ -f "$DEST_FILE" ]; then
    DEST_OLD_BYTES=$(wc -c < "$DEST_FILE" 2>/dev/null || echo 0)
    DEST_OLD_KB=$(( DEST_OLD_BYTES / 1024 ))
fi
DEST_FREE_KB=$(df -Pk "$DEST_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
[ -z "$DEST_FREE_KB" ] && DEST_FREE_KB=0
if [ "$ENGINE" = "upstream" ]; then
    BIN_KB=$(( (BIN_BYTES + 1023) / 1024 ))
    NEED_KB=$(( BIN_KB + 2048 ))
else
    NEED_KB=$ROOT_NEED_KB
fi
AVAIL_KB=$(( DEST_FREE_KB + DEST_OLD_KB ))
if [ "$AVAIL_KB" -lt "$NEED_KB" ]; then
    die "Not enough space in $DEST_DIR: need ~$(( NEED_KB / 1024 )) MB, available ~$(( AVAIL_KB / 1024 )) MB (free $(( DEST_FREE_KB / 1024 )) MB + old binary $(( DEST_OLD_KB / 1024 )) MB)."
fi

if [ -n "$SERVICE" ] && [ -x "/etc/init.d/$SERVICE" ]; then
    say "Stopping $SERVICE..."
    "/etc/init.d/$SERVICE" stop >/dev/null 2>&1
    killall sing-box >/dev/null 2>&1
    sleep 2
    SERVICE_STOPPED=1
fi

if [ "$ENGINE" = "upstream" ]; then
    say "Installing $DEST_FILE..."
    rm -f "$DEST_FILE" "${DEST_FILE}.tmp"
    cp -f "$BIN" "${DEST_FILE}.tmp" || die "Failed to write ${DEST_FILE}.tmp (out of space?)."
    chmod +x "${DEST_FILE}.tmp"
    mv -f "${DEST_FILE}.tmp" "$DEST_FILE" || die "Failed to replace $DEST_FILE."
else
    # The package managers check free space without knowing the old raw
    # binary will be replaced, so remove it up front.
    rm -f "$DEST_FILE"
    if [ "$PKG" = "apk" ]; then
        if apk info 2>/dev/null | grep -q '^sing-box$'; then
            say "Removing the installed sing-box package..."
            apk del sing-box >/dev/null 2>&1 || warn "apk del sing-box failed (continuing)."
        fi
        say "Installing the $PKG_NAME package..."
        apk add --allow-untrusted --force-reinstall "$WORK_DIR/$ASSET" || die "apk add failed."
    else
        if opkg list-installed 2>/dev/null | grep -q '^sing-box '; then
            say "Removing the installed sing-box package..."
            opkg remove --force-depends sing-box >/dev/null 2>&1 || warn "opkg remove sing-box failed (continuing)."
        fi
        say "Installing the $PKG_NAME package..."
        opkg install --force-reinstall "$WORK_DIR/$ASSET" || die "opkg install failed (not enough space in /overlay?)."
    fi
fi

# EikeiDev UPX variant leftovers: the real binary lives elsewhere and this
# path is only a wrapper.
rm -f /usr/libexec/sing-box-core /etc/sing-box-version.cache

INSTALLED=$("$DEST_FILE" version 2>/dev/null | head -n 1)
say "Installed: ${INSTALLED:-failed to get the version}"

if [ -n "$SERVICE" ] && [ -x "/etc/init.d/$SERVICE" ]; then
    say "Starting $SERVICE..."
    if "/etc/init.d/$SERVICE" start >/dev/null 2>&1; then
        SERVICE_STOPPED=0
    else
        warn "Failed to start $SERVICE, check the logs."
    fi
fi
say "Done."
