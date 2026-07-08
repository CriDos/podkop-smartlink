# Daemon loop for podkop-smartlink

# Cleanup on exit: persist current selection, remove locks, temp files.
_sl_daemon_cleanup() {
    sl_cur_persist 2>/dev/null
    [ -n "$SL_SYNC_LOCK_TOKEN" ] && sl_lock_release "$STATE_SYNC_LOCK" "$SL_SYNC_LOCK_TOKEN"
    rm -f "${STATE_PID}" 2>/dev/null
    rm -f "${STATE_DIR}"/stats.* "${STATE_DIR}"/keymap.* "${STATE_DIR}"/status_data.* 2>/dev/null
    rm -f "${STATE_DIR}"/src_*.tmp "${STATE_DIR}"/*.excluded.work 2>/dev/null
    log "SmartLink daemon stopped" "info"
}

sl_daemon_run() {
    mkdir -p "$STATE_DIR" "$STATE_HISTORY_DIR"
    local work="${STATE_DIR}/links.work"

    local fail_count=0
    local last_stats_ping=0
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
        if sl_refresh_active; then
            # Stale check: if refresh lock is older than 150s, remove it
            local ref_age
            ref_age=$(( now - $(sl_safe_num "$(sl_file_mtime "$STATE_REFRESH_LOCK")") ))
            if [ "$ref_age" -gt 150 ]; then
                log "Removing stale refresh lock (age=${ref_age}s)" "warn"
                sl_refresh_finish "$(sl_refresh_token)"
            else
                sleep 5
                continue
            fi
        fi

        if [ -z "$(sl_source_list)" ]; then
            if sl_lock_active "$STATE_SYNC_LOCK"; then
                sleep "$check_sec"
                continue
            fi
            sl_sel_release_podkop "$SL_CFG_TARGET_SECTION" >/dev/null 2>&1 || true
            rm -f "$STATE_LINKS_CACHE" "$STATE_LINKS_FULL" "$STATE_LINKS_EXCLUDED" "$STATE_TAGS_CACHE" \
                "$STATE_LAST_PING" "$work" "${work}.excluded" 2>/dev/null
            sl_cur_clear
            fetch_fail_count=0
            fetch_backoff=0
            sleep "$check_sec"
            continue
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

        # --- periodic Stats ping (skip first iteration after boot) ---
        local stats_interval since_stats
        stats_interval="$SL_CFG_STATS_PING_INTERVAL"
        [ "$stats_interval" -lt 15 ] && stats_interval=15
        if [ "$last_stats_ping" -eq 0 ]; then
            last_stats_ping="$now"
        fi
        since_stats=$(( now - last_stats_ping ))
        if [ "$since_stats" -ge "$stats_interval" ]; then
            if ! sl_refresh_active; then
                sl_sel_stats_ping "$group_tag" "$full_links"
                last_stats_ping="$now"
            fi
        fi

        # --- ensure current selection is valid ---
        if sl_refresh_active; then
            sleep 5
            continue
        fi
        if ! sl_sel_current_valid "$full_links" "$group_tag"; then
            log "No valid current selection, choosing by ping" "info"
            # After reboot, keep the last selected URL only if it is healthy.
            local preferred_url=""
            if [ ! -f "$STATE_CURRENT" ]; then
                preferred_url="$(uci -q get "$SL_NAME.main.last_selected" 2>/dev/null)"
            fi
            if ! sl_sel_ping_all "$group_tag" "$full_links" "$preferred_url"; then
                log "No healthy servers, refreshing subscription" "warn"
                sl_sel_sync "$work"
                [ -s "$STATE_LINKS_FULL" ] && full_links="$STATE_LINKS_FULL"
                if sl_sel_ping_all "$group_tag" "$full_links"; then
                    fail_count=0
                    last_stats_ping="$now"
                    sleep "$check_sec"
                    continue
                fi
                log "No healthy servers and no new links, waiting" "warn"
                sleep "$((check_sec * 3))"
                continue
            fi
            fail_count=0
            last_stats_ping="$now"
            sleep "$check_sec"
            continue
        fi

        # --- sticky health-check of current ---
        if sl_refresh_active; then
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

        if [ "$fail_count" -lt "$SL_CFG_FAIL_COUNT" ]; then
            log "Current check failed ($fail_count/$SL_CFG_FAIL_COUNT) lat=${lat:-none} threshold=${SL_CFG_MAX_PING}ms" "debug"
            sleep "$check_sec"
            continue
        fi

        # N failures reached — ping all and switch only if healthy servers exist
        fail_count=0
        log "Fail threshold reached, pinging all" "info"
        if sl_sel_ping_all "$group_tag" "$full_links"; then
            last_stats_ping="$now"
            sleep "$check_sec"
            continue
        fi

        # No healthy servers — refresh subscription and retry once
        log "No healthy servers after full ping, refreshing subscription" "warn"
        sl_sel_sync "$work"
        [ -s "$STATE_LINKS_FULL" ] && full_links="$STATE_LINKS_FULL"
        if sl_sel_ping_all "$group_tag" "$full_links"; then
            last_stats_ping="$now"
            sleep "$check_sec"
            continue
        fi

        # Nothing worked — back off
        log "All servers down, backing off" "warn"
        sleep "$((check_sec * 5))"
    done
}
