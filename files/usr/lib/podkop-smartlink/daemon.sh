# Daemon loop for podkop-smartlink

# Cleanup on exit: persist current selection, remove locks, temp files.
_sl_daemon_cleanup() {
    sl_cur_persist 2>/dev/null
    rm -rf "${STATE_DIR}/sync.lock" 2>/dev/null
    rm -f "${STATE_DIR}/refreshing" 2>/dev/null
    rm -f "${STATE_PID}" 2>/dev/null
    rm -f "${STATE_DIR}"/stats.* "${STATE_DIR}"/keymap.* "${STATE_DIR}"/status_data.* 2>/dev/null
    rm -f "${STATE_DIR}"/src_*.tmp 2>/dev/null
    log "SmartLink daemon stopped" "info"
}

sl_daemon_run() {
    mkdir -p "$STATE_DIR" "$STATE_HISTORY_DIR"
    local work="${STATE_DIR}/links.work"

    local fail_count=0
    local last_display_ping=0
    local last_detect=0
    local fetch_fail_count=0
    local fetch_backoff=0

    # Persist current selection URL to UCI for cross-reboot restore
    if [ -f "$STATE_CURRENT" ]; then
        sl_cur_persist 2>/dev/null
    fi

    # Signal handling for clean shutdown (TERM/INT only, not EXIT to avoid double-fire)
    trap '_sl_daemon_cleanup; exit 0' INT TERM

    log "SmartLink daemon started (section=$SL_CFG_TARGET_SECTION)" "info"

    local check_sec="${SL_CFG_CHECK_INTERVAL:-10}"
    [ "$check_sec" -lt 5 ] && check_sec=5

    while :; do
        sl_cfg_load
        check_sec="${SL_CFG_CHECK_INTERVAL:-10}"
        [ "$check_sec" -lt 5 ] && check_sec=5
        local now
        now="$(date +%s)"

        # --- periodic clash API re-detection (every 5 min) ---
        if [ $((now - last_detect)) -gt 300 ]; then
            sl_clash_redetect 2>/dev/null
            last_detect="$now"
        fi

        # group_tag is re-evaluated each iteration (target_section may change)
        local group_tag
        group_tag="$(sl_clash_group_tag "$SL_CFG_TARGET_SECTION")"

        # --- periodic subscription refresh ---
        # Skip if apply_changes is running in background
        if [ -f "${STATE_DIR}/refreshing" ]; then
            # Stale check: if refreshing file is older than 150s, remove it
            local ref_age
            ref_age=$(( now - $(date -r "${STATE_DIR}/refreshing" +%s 2>/dev/null || echo 0) ))
            if [ "$ref_age" -gt 150 ]; then
                log "Removing stale refreshing flag (age=${ref_age}s)" "warn"
                rm -f "${STATE_DIR}/refreshing" 2>/dev/null
                rm -rf "${STATE_DIR}/sync.lock" 2>/dev/null
            else
                sleep 5
                continue
            fi
        fi
        local update_sec since_update need_refresh
        update_sec="$(sl_interval_to_sec "$SL_CFG_UPDATE_INTERVAL")"
        since_update=$(( now - $(sl_safe_num "$(sl_last_update)") ))
        need_refresh=0
        [ "$since_update" -ge "$update_sec" ] && need_refresh=1
        [ ! -f "$STATE_LINKS_CACHE" ] && need_refresh=1

        if [ "$need_refresh" -eq 1 ]; then
            # Backoff: skip refresh if we've been failing repeatedly
            if [ "$fetch_backoff" -gt 0 ]; then
                fetch_backoff=$((fetch_backoff - 1))
                log "Skipping refresh (backoff: $fetch_backoff iterations left)" "debug"
            else
                sl_sel_sync "$work"
                local sync_rc=$?
                [ "$sync_rc" -eq 2 ] && { sleep "$check_sec"; continue; }
                if [ "$sync_rc" -eq 1 ]; then
                    fetch_fail_count=$((fetch_fail_count + 1))
                    if [ "$fetch_fail_count" -ge 3 ]; then
                        fetch_backoff=$((fetch_fail_count * 2))
                        if [ "$fetch_backoff" -gt 30 ]; then fetch_backoff=30; fi
                        log "Fetch failed ${fetch_fail_count}x, backing off ${fetch_backoff} cycles" "warn"
                    fi
                else
                    [ "$sync_rc" -eq 0 ] && fail_count=0
                    fetch_fail_count=0
                    fetch_backoff=0
                fi
            fi
        fi

        local full_links="$STATE_LINKS_FULL"
        [ -s "$full_links" ] || { sleep "$check_sec"; continue; }

        # --- periodic display ping (skip first iteration after boot) ---
        local display_interval since_display
        display_interval="$SL_CFG_PING_ALL_INTERVAL"
        [ "$display_interval" -lt 15 ] && display_interval=15
        since_display=$(( now - last_display_ping ))
        if [ "$last_display_ping" -gt 0 ] && [ "$since_display" -ge "$display_interval" ]; then
            if [ ! -f "${STATE_DIR}/refreshing" ]; then
                sl_sel_display_ping "$group_tag" "$full_links"
                last_display_ping="$now"
            fi
        fi

        # --- ensure current selection is valid ---
        if [ -f "${STATE_DIR}/refreshing" ]; then
            sleep 5
            continue
        fi
        if ! sl_sel_current_valid "$full_links" "$group_tag"; then
            log "No valid current selection, choosing by ping" "info"
            # After reboot, pass saved URL for stickiness preference
            local sticky_url=""
            if [ ! -f "$STATE_CURRENT" ]; then
                sticky_url="$(uci -q get "$SL_NAME.main.last_selected" 2>/dev/null)"
            fi
            if ! sl_sel_ping_all "$group_tag" "$full_links" "$sticky_url"; then
                log "No alive servers, refreshing subscription" "warn"
                sl_sel_sync "$work"
                [ -s "$STATE_LINKS_FULL" ] && full_links="$STATE_LINKS_FULL"
                if sl_sel_ping_all "$group_tag" "$full_links"; then
                    fail_count=0
                    last_display_ping="$now"
                    sleep "$check_sec"
                    continue
                fi
                log "No alive servers and no new links, waiting" "warn"
                sleep "$((check_sec * 3))"
                continue
            fi
            fail_count=0
            last_display_ping="$now"
            sleep "$check_sec"
            continue
        fi

        # --- sticky health-check of current ---
        if [ -f "${STATE_DIR}/refreshing" ]; then
            sleep 5
            continue
        fi
        local cur_tag lat cur_url
        cur_url="$(sl_cur_url)"
        cur_tag="$(sl_sel_resolve_current "$full_links" "$group_tag" "$cur_url")"
        if [ -z "$cur_tag" ]; then
            log "Current tag unresolved (group changed?), re-selecting" "warn"
            sl_cur_clear
            sleep "$check_sec"
            continue
        fi

        lat="$(sl_clash_proxy_latency "$cur_tag" "$SL_CFG_PING_TIMEOUT")"

        local lat_ok=0
        if [ -n "$lat" ] && [ "$lat" != "null" ]; then
            case "$lat" in *[!0-9]*) ;; *) [ "$lat" -le "$SL_CFG_MAX_PING" ] && lat_ok=1 ;; esac
        fi
        if [ "$lat_ok" -eq 1 ]; then
            fail_count=0
            sl_hist_append "$cur_url" "$lat" 1
            log "Current OK: ${lat}ms (threshold ${SL_CFG_MAX_PING})" "debug"
            # Sync group if it drifted (e.g. after reload)
            local group_now
            group_now="$(sl_clash_get_group_now "$group_tag" 2>/dev/null)"
            [ "$group_now" != "$cur_tag" ] && sl_clash_set_group "$group_tag" "$cur_tag" 2>/dev/null
            sleep "$check_sec"
            continue
        fi

        # Current degraded or dead
        fail_count=$((fail_count + 1))
        sl_hist_append "$cur_url" "${lat:-}" 0
        log "Current degraded/dead (fail $fail_count/$SL_CFG_FAIL_COUNT) lat=${lat:-none} threshold=$SL_CFG_MAX_PING" "warn"

        if [ "$fail_count" -lt "$SL_CFG_FAIL_COUNT" ]; then
            sleep "$check_sec"
            continue
        fi

        # N failures reached — ping all and switch if alive exist
        fail_count=0
        log "Fail threshold reached, pinging all" "info"
        if sl_sel_ping_all "$group_tag" "$full_links"; then
            last_display_ping="$now"
            sleep "$check_sec"
            continue
        fi

        # No alive — refresh subscription and retry once
        log "No alive after full ping, refreshing subscription" "warn"
        sl_sel_sync "$work"
        [ -s "$STATE_LINKS_FULL" ] && full_links="$STATE_LINKS_FULL"
        if sl_sel_ping_all "$group_tag" "$full_links"; then
            last_display_ping="$now"
            sleep "$check_sec"
            continue
        fi

        # Nothing worked — back off
        log "All servers down, backing off" "warn"
        sleep "$((check_sec * 5))"
    done
}
