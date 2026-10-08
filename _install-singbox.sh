#!/bin/sh
# sing-box installer for OpenWrt: sing-box-lx (recommended) or the original
# sing-box (upstream SagerNet).
#
# Usage (interactive menu):
#   sh <(wget -qO- https://raw.githubusercontent.com/CriDos/podkop-smartlink/main/_install-singbox.sh)
#
# Non-interactive (the menu is shown only when stdin is a TTY):
#   ENGINE=lx|upstream sh _install-singbox.sh
#
# Environment overrides:
#   ENGINE=lx|upstream     engine to install: latest stable (skips the menu)
#   MENU=1|0               force/disable the menu (0 also useful for cron)
#   DEST_FILE=/usr/bin/sing-box   target path
#   SERVICE=podkop         service to stop/start (default: auto-detect podkop/sing-box, empty = skip)
#
# The old binary is replaced in place: no backup copy is kept, and free space
# (counted together with the space the old binary frees) is checked before
# the service is stopped.
#
# sing-box-lx is Leadaxe's thin upstream 1.14.x fork with XHTTP et al:
# https://github.com/Leadaxe/sing-box-lx
# Upstream sing-box releases: https://github.com/SagerNet/sing-box

[ -f /etc/openwrt_release ] || { echo "Error: this is not OpenWrt."; exit 1; }
. /etc/openwrt_release

DEST_FILE="${DEST_FILE:-/usr/bin/sing-box}"
ENGINE="${ENGINE:-}"
SERVICE_STOPPED=0
MIRROR_PREFIX="https://ghproxy.net/"
WORK_DIR="/tmp/lx-install"
LX_REPO="Leadaxe/sing-box-lx"
UP_REPO="SagerNet/sing-box"
RECOMMENDED_LX="1.14.2-lx.12"
RECOMMENDED_UP="1.14.2"

R=""; G=""; Y=""; N=""
if [ -t 1 ]; then
    R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; N="\033[0m"
fi
say()  { printf "$G[*]${N} %s\n" "$1"; }
warn() { printf "$Y[!]${N} %s\n" "$1"; }
die()  { printf "$R[x]${N} %s\n" "$1"; rm -f "${DEST_FILE}.tmp"; rm -rf "$WORK_DIR"; exit 1; }

case "$DISTRIB_ARCH" in
    aarch64*)
        LX_ARCH="arm64"; UP_ARCH="arm64-musl" ;;
    arm_cortex-a7*|arm_cortex-a9*|arm_cortex-a15*)
        LX_ARCH="armv7"; UP_ARCH="armv7-musl" ;;
    x86_64)
        LX_ARCH="amd64"; UP_ARCH="amd64-musl" ;;
    mipsel_24kc|mipsel_*)
        LX_ARCH="mipsle-softfloat"; UP_ARCH="mipsle-softfloat-musl" ;;
    mips_24kc|mips_*)
        LX_ARCH="mips-softfloat"; UP_ARCH="mips-softfloat" ;;
    *) die "Architecture $DISTRIB_ARCH is not supported (no armv6/386 builds)." ;;
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

# Latest stable sing-box-lx tag (without the leading v), prereleases filtered out.
github_latest_lx() {
    local releases
    releases=$(fetch "https://api.github.com/repos/$LX_REPO/releases?per_page=30" 2>/dev/null) || return 1
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
    local lx_latest up_latest choice
    say "Querying GitHub for the latest releases..."
    lx_latest=$(github_latest_lx 2>/dev/null || true)
    up_latest=$(github_latest_upstream 2>/dev/null || true)
    [ -n "$lx_latest" ] || lx_latest="unavailable"
    [ -n "$up_latest" ] || up_latest="unavailable"

    printf '\nSelect what to install:\n'
    printf '  1) sing-box-lx %s (recommended)\n' "$RECOMMENDED_LX"
    printf '  2) sing-box-lx latest stable (%s)\n' "$lx_latest"
    printf '  3) sing-box (original) latest stable (%s)\n' "$up_latest"
    printf 'Choice [1]: '
    read -r choice || choice=""
    case "$choice" in
        2) ENGINE="lx"; VERSION="$lx_latest" ;;
        3) ENGINE="upstream"; VERSION="$up_latest" ;;
        *) ENGINE="lx"; VERSION="$RECOMMENDED_LX" ;;
    esac
    if [ -z "$VERSION" ] || [ "$VERSION" = "unavailable" ]; then
        die "No usable version selected."
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

[ -n "$ENGINE" ] || ENGINE="lx"

if [ -z "$VERSION" ]; then
    case "$ENGINE" in
        lx)
            VERSION=$(github_latest_lx 2>/dev/null || true)
            if [ -z "$VERSION" ]; then
                warn "GitHub API unavailable, falling back to pinned version $RECOMMENDED_LX."
                VERSION="$RECOMMENDED_LX"
            fi
            ;;
        upstream)
            VERSION=$(github_latest_upstream 2>/dev/null || true)
            if [ -z "$VERSION" ]; then
                warn "GitHub API unavailable, falling back to pinned version $RECOMMENDED_UP."
                VERSION="$RECOMMENDED_UP"
            fi
            ;;
        *) die "Unknown ENGINE '$ENGINE' (expected lx or upstream)." ;;
    esac
fi

case "$ENGINE" in
    lx)
        REPO="$LX_REPO"
        ASSET="sing-box-$VERSION-linux-$LX_ARCH.tar.gz" ;;
    upstream)
        REPO="$UP_REPO"
        ASSET="sing-box-$VERSION-linux-$UP_ARCH.tar.gz" ;;
    *) die "Unknown ENGINE '$ENGINE' (expected lx or upstream)." ;;
esac
BASE_URL="https://github.com/$REPO/releases/download/v$VERSION"
URL="$BASE_URL/$ASSET"
say "Engine: $ENGINE, version: $VERSION, asset: $ASSET"

TMP_NEED_KB=130000
TMP_FREE=$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')
[ -z "$TMP_FREE" ] && TMP_FREE=0
if [ "$TMP_FREE" -lt "$TMP_NEED_KB" ]; then
    ROOT_FREE=$(df -Pk /root 2>/dev/null | awk 'NR==2 {print $4}')
    [ -z "$ROOT_FREE" ] && ROOT_FREE=0
    if [ "$ROOT_FREE" -ge "$TMP_NEED_KB" ]; then
        WORK_DIR="/root/lx-install"
        warn "Low space in /tmp, using $WORK_DIR."
    else
        die "Not enough free space (need ~130 MB in /tmp or /root)."
    fi
fi
rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR" || die "Failed to create $WORK_DIR."
trap '[ "$SERVICE_STOPPED" = "1" ] && [ -n "$SERVICE" ] && "/etc/init.d/$SERVICE" start >/dev/null 2>&1; rm -rf "$WORK_DIR"' EXIT INT TERM

say "Downloading archive..."
if ! download "$URL" "$WORK_DIR/$ASSET"; then
    warn "Direct download failed, trying mirror $MIRROR_PREFIX..."
    download "${MIRROR_PREFIX}${URL}" "$WORK_DIR/$ASSET" || die "Download failed both directly and via the mirror."
fi
[ -s "$WORK_DIR/$ASSET" ] || die "Downloaded archive is empty."

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

if [ "${SERVICE-unset}" = "unset" ]; then
    if [ -f /etc/init.d/podkop ]; then SERVICE="podkop"
    elif [ -f /etc/init.d/sing-box ]; then SERVICE="sing-box"
    else SERVICE=""; fi
fi

if [ -f "$DEST_FILE" ]; then
    OLD_VER=$("$DEST_FILE" version 2>/dev/null | head -n 1)
    say "Current binary: ${OLD_VER:-unknown}"
fi

# Pre-flight: the old binary is removed before the new one is written, so the
# destination filesystem must hold the new binary plus a small margin
# (measured as free space plus the space the old binary will free). Checked
# before the service is stopped so a full disk cannot leave the router
# without a running engine. No backup copy is kept.
BIN_BYTES=$(wc -c < "$BIN")
BIN_KB=$(( (BIN_BYTES + 1023) / 1024 ))
DEST_OLD_KB=0
if [ -f "$DEST_FILE" ]; then
    DEST_OLD_BYTES=$(wc -c < "$DEST_FILE" 2>/dev/null || echo 0)
    DEST_OLD_KB=$(( DEST_OLD_BYTES / 1024 ))
fi
DEST_DIR=$(dirname "$DEST_FILE")
mkdir -p "$DEST_DIR" 2>/dev/null || true
DEST_FREE_KB=$(df -Pk "$DEST_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
[ -z "$DEST_FREE_KB" ] && DEST_FREE_KB=0
NEED_KB=$(( BIN_KB + 2048 ))
AVAIL_KB=$(( DEST_FREE_KB + DEST_OLD_KB ))
if [ "$AVAIL_KB" -lt "$NEED_KB" ]; then
    die "Not enough space in $DEST_DIR: need ~$(( BIN_KB / 1024 )) MB, available ~$(( AVAIL_KB / 1024 )) MB (free $(( DEST_FREE_KB / 1024 )) MB + old binary $(( DEST_OLD_KB / 1024 )) MB)."
fi

if [ -n "$SERVICE" ] && [ -x "/etc/init.d/$SERVICE" ]; then
    say "Stopping $SERVICE..."
    "/etc/init.d/$SERVICE" stop >/dev/null 2>&1
    killall sing-box >/dev/null 2>&1
    sleep 2
    SERVICE_STOPPED=1
fi

say "Installing $DEST_FILE..."
rm -f "$DEST_FILE" "${DEST_FILE}.tmp"
cp -f "$BIN" "${DEST_FILE}.tmp" || die "Failed to write ${DEST_FILE}.tmp (out of space?)."
chmod +x "${DEST_FILE}.tmp"
mv -f "${DEST_FILE}.tmp" "$DEST_FILE" || die "Failed to replace $DEST_FILE."

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
