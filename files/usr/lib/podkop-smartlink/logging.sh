# Logging for podkop-smartlink
# Uses logger(1) to systemd-style syslog (OpenWrt uses logd).

log() {
    local message="$1"
    local level="${2:-info}"
    local tag="$SL_NAME"

    local prio
    case "$level" in
        debug) prio=7 ;;
        info)  prio=6 ;;
        warn)  prio=4 ;;
        error) prio=3 ;;
        fatal) prio=2 ;;
        *)     prio=6 ;;
    esac

    logger -t "$tag" -p "$prio" "$message" 2>/dev/null

    # Also echo to stdout/stderr when running interactively (CLI) or as procd daemon
    if [ "$SL_DAEMON" = "1" ] || [ -t 1 ]; then
        case "$level" in
            error|fatal) printf '%s [%s] %s\n' "$tag" "$level" "$message" >&2 ;;
            *)           printf '%s [%s] %s\n' "$tag" "$level" "$message" ;;
        esac
    fi
}
