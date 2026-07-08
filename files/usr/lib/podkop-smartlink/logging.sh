# Logging for podkop-smartlink
# Uses logger(1) to systemd-style syslog (OpenWrt uses logd).

log() {
    local message="$1"
    local level="${2:-info}"
    local tag="$SL_NAME"

    if [ "$level" = "debug" ]; then
        case "${SL_DEBUG:-0}" in
            1|true|yes|on) ;;
            *)
                case "${SL_CFG_DEBUG:-0}" in
                    1|true|yes|on) ;;
                    *) return 0 ;;
                esac
                ;;
        esac
    fi

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

    # Echo only for an interactive CLI. procd captures daemon stdout into syslog.
    if [ -t 1 ]; then
        case "$level" in
            error|fatal) printf '%s [%s] %s\n' "$tag" "$level" "$message" >&2 ;;
            *)           printf '%s [%s] %s\n' "$tag" "$level" "$message" ;;
        esac
    fi
}
