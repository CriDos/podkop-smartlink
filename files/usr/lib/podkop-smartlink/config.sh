# Config helpers for podkop-smartlink (UCI reads with defaults)

# Read a UCI option from smartlink.main with a default.
sl_cfg() {
    local val
    val="$(uci -q get "$SL_NAME.main.$1" 2>/dev/null)"
    [ -z "$val" ] && val="$2"
    echo "$val"
}

# Read a UCI boolean option.
sl_cfg_bool() {
    local val
    val="$(uci -q get "$SL_NAME.main.$1" 2>/dev/null)"
    case "$val" in
        1|on|true|enabled) echo 1 ;;
        *) echo "${2:-0}" ;;
    esac
}

# Read a UCI integer option, coercing non-numeric to default.
sl_cfg_int() {
    local val
    val="$(uci -q get "$SL_NAME.main.$1" 2>/dev/null)"
    case "$val" in
        ''|*[!0-9]*) echo "$2" ;;
        *) echo "$val" ;;
    esac
}

# Convert an interval string (Ns/Nm/Nh/Nd) to seconds.
sl_interval_to_sec() {
    local v="$1"
    local n
    [ -z "$v" ] && echo 3600 && return
    case "$v" in
        *s) n="${v%s}"; case "$n" in ''|*[!0-9]*) echo 3600 ;; *) echo "$n" ;; esac ;;
        *m) n="${v%m}"; case "$n" in ''|*[!0-9]*) echo 3600 ;; *) echo "$(( n * 60 ))" ;; esac ;;
        *h) n="${v%h}"; case "$n" in ''|*[!0-9]*) echo 3600 ;; *) echo "$(( n * 3600 ))" ;; esac ;;
        *d) n="${v%d}"; case "$n" in ''|*[!0-9]*) echo 3600 ;; *) echo "$(( n * 86400 ))" ;; esac ;;
        *[!0-9]*) echo 3600 ;;
        *) echo "$v" ;;
    esac
}

# Read all config into SL_CFG_* globals.
sl_cfg_load() {
    SL_CFG_TARGET_SECTION="$(sl_cfg target_section "$PODKOP_SECTION_DEFAULT")"
    SL_CFG_UPDATE_INTERVAL="$(sl_cfg update_interval "$DEFAULT_UPDATE_INTERVAL")"
    SL_CFG_CHECK_INTERVAL="$(sl_cfg_int check_interval "$DEFAULT_CHECK_INTERVAL")"
    SL_CFG_MAX_PING="$(sl_cfg_int max_ping "$DEFAULT_MAX_PING")"
    SL_CFG_FAIL_COUNT="$(sl_cfg_int fail_count "$DEFAULT_FAIL_COUNT")"
    SL_CFG_PING_TIMEOUT="$(sl_cfg_int ping_timeout "$DEFAULT_PING_TIMEOUT")"
    SL_CFG_TEST_URL="$(sl_cfg test_url "$DEFAULT_TEST_URL")"
    SL_CFG_STATS_PING_INTERVAL="$(sl_cfg_int ping_all_interval "$DEFAULT_STATS_PING_INTERVAL")"
    SL_CFG_XHTTP="$(sl_cfg_bool xhttp 0)"
    SL_CFG_USE_PRIORITY="$(sl_cfg_bool use_priority "$DEFAULT_USE_PRIORITY")"
}
