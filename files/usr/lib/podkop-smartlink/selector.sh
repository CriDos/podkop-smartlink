# Core sticky selection logic for podkop-smartlink

# Map an ordered links_file to outbound tags from the live group.
# Output: "<tag>\t<url>\t<title>\t<host>\t<src_idx>" per line, index-aligned with links_file.
# Returns 1 if group unavailable.
sl_sel_map() {
    local links_file="$1" group_tag="$2"
    local tags
    tags="$(sl_clash_get_outbound_tags "$group_tag" 2>/dev/null)" || return 1
    [ -z "$tags" ] && return 1

    # Sanity: tag count should match non-empty link count
    local tag_count link_count
    tag_count="$(printf '%s\n' "$tags" | grep -c . 2>/dev/null || echo 0)"
    link_count="$(grep -c . "$links_file" 2>/dev/null || echo 0)"
    case "$tag_count" in *[!0-9]*) tag_count=0 ;; esac
    case "$link_count" in *[!0-9]*) link_count=0 ;; esac
    if [ "$tag_count" -ne "$link_count" ]; then
        log "Tag/link count mismatch ($tag_count tags vs $link_count links), group may be reloading" "warn"
        return 1
    fi

    awk -F "$TAB" -v tags="$tags" '
        BEGIN {
            nt = split(tags, tarr, "\n")
            OFS = "\t"
        }
        $1 != "" {
            i++
            print (i <= nt ? tarr[i] : ""), $1, $2, $3, (NF >= 4 ? $4 : "0")
        }
    ' "$links_file"
}

# Build a tag->link map file (single /proxies fetch).
# Args: <group_tag> <links_file> <map_out_file>
sl_sel_build_map() {
    sl_sel_map "$2" "$1" > "$3" 2>/dev/null
}

# Look up a tag in a prebuilt map file.
# Echoes "<url>\t<title>\t<host>". Empty if not found.
sl_sel_lookup() {
    awk -F "$TAB" -v t="$2" '$1==t{print $2"\t"$3"\t"$4; exit}' "$1" 2>/dev/null
}

# Resolve the tag for the current selected URL (re-map after reload).
# Args: <links_file> <group_tag>
# Echoes tag (or empty). Updates current state tag.
sl_sel_resolve_current() {
    local links_file="$1" group_tag="$2"
    local cur_url="${3:-$(sl_cur_url)}"
    [ -z "$cur_url" ] && { echo ""; return; }

    local tags
    tags="$(sl_clash_get_outbound_tags "$group_tag" 2>/dev/null)"
    [ -z "$tags" ] && { echo ""; return; }

    local tag
    tag="$(awk -F "$TAB" -v tags="$tags" -v u="$cur_url" '
        BEGIN { nt = split(tags, tarr, "\n") }
        $1 != "" {
            i++
            if ($1 == u && i <= nt) { print tarr[i]; exit }
        }
    ' "$links_file" 2>/dev/null)"
    sl_cur_update_tag "$tag"
    echo "$tag"
}

# Pick the best alive tag using score-based selection.
# Score = latency + priority_penalty - stickiness_bonus
# Lower score = better.
# Args: <ping_file> <map_file> <current_url> <use_priority>
# Echoes "<tag>" (best tag, or empty if none alive).
sl_sel_pick_best() {
    local ping_file="$1" map_file="$2" cur_url="$3" use_priority="$4"

    awk -F "$TAB" -v map_file="$map_file" -v cur_url="$cur_url" -v use_priority="$use_priority" '
        BEGIN {
            while ((getline line < map_file) > 0) {
                split(line, a, "\t")
                tag_url[a[1]] = a[2]
                tag_src[a[1]] = a[5] + 0
            }
            close(map_file)
            best_score = 999999
            best_tag = ""
        }
        $1 != "" {
            tag = $2
            lat = $1 + 0
            url = tag_url[tag]
            src_idx = tag_src[tag]

            stickiness = (url == cur_url) ? -200 : 0
            priority = (use_priority == "1") ? (src_idx * 50) : 0

            score = lat + stickiness + priority
            if (score < best_score) {
                best_score = score
                best_tag = tag
            }
        }
        END {
            if (best_tag != "") print best_tag
        }
    ' "$ping_file" 2>/dev/null
}

# Select a specific tag and record current state.
# Args: <group_tag> <links_file> <tag> [map_file]
sl_sel_select() {
    local group_tag="$1" links_file="$2" tag="$3" map_file="$4"
    [ -z "$tag" ] && return 1

    local link url title
    if [ -n "$map_file" ] && [ -s "$map_file" ]; then
        link="$(sl_sel_lookup "$map_file" "$tag")"
    else
        link="$(sl_sel_map "$links_file" "$group_tag" 2>/dev/null | awk -F "$TAB" -v t="$tag" '$1==t{print $2"\t"$3"\t"$4; exit}')"
    fi
    url="$(printf '%s' "$link" | cut -f1)"
    title="$(printf '%s' "$link" | cut -f2)"

    [ -z "$url" ] && { log "Cannot resolve link for tag '$tag'" "warn"; return 1; }

    if sl_clash_set_group "$group_tag" "$tag"; then
        sl_cur_set "$url" "$tag" "$title"
        log "Selected: $title ($tag)" "info"
        return 0
    fi
    return 1
}

# Ping all outbounds, record history, pick best alive, select it.
# Args: <group_tag> <links_file> [sticky_url] [ping_out_file]
# sticky_url gives -50ms bonus in score (prefer last selection after reboot).
# Returns 1 if no alive.
sl_sel_ping_all() {
    local group_tag="$1" links_file="$2" sticky_url="${3:-}"
    local ping_file="${4:-${STATE_DIR}/ping.$$}"
    local timeout="$SL_CFG_PING_TIMEOUT"

    if ! sl_clash_ping_group "$group_tag" "$ping_file" "$timeout"; then
        log "Could not ping group '$group_tag'" "warn"
        rm -f "$ping_file"
        return 1
    fi

    cp "$ping_file" "${STATE_LAST_PING}.tmp" 2>/dev/null && mv "${STATE_LAST_PING}.tmp" "$STATE_LAST_PING"
    log "Ping all: $SL_ALIVE_COUNT alive" "debug"

    if [ "$SL_ALIVE_COUNT" -le 0 ]; then
        rm -f "$ping_file"
        return 1
    fi

    local map_file="${ping_file}.map"
    sl_sel_build_map "$group_tag" "$links_file" "$map_file"
    [ -s "$map_file" ] || { rm -f "$ping_file"; return 1; }

    # Record history for all tested servers (single unified call)
    sl_hist_record_pings "$ping_file" "$map_file"

    # Score-based best selection (stickiness + priority)
    local cur_url tag
    cur_url="$(sl_cur_url)"
    [ -z "$cur_url" ] && cur_url="$sticky_url"
    tag="$(sl_sel_pick_best "$ping_file" "$map_file" "$cur_url" "$SL_CFG_USE_PRIORITY")"

    rm -f "$ping_file"
    [ -z "$tag" ] && { rm -f "$map_file"; return 1; }

    sl_sel_select "$group_tag" "$links_file" "$tag" "$map_file"
    local rc=$?
    rm -f "$map_file"
    return $rc
}

# Background ping of ALL servers for dashboard display only.
# Saves results to STATE_LAST_PING and records history, does NOT switch.
# Args: <group_tag> <links_file>
sl_sel_display_ping() {
    local group_tag="$1" links_file="$2"
    local ping_file="${STATE_DIR}/ping.display"

    # Batched parallel ping (sequential was too slow through NAT)
    if ! sl_clash_ping_group "$group_tag" "$ping_file" "$SL_CFG_PING_TIMEOUT" 0; then
        log "Display ping: could not ping group" "debug"
        rm -f "$ping_file"
        return 1
    fi

    # Always update STATE_LAST_PING (stale data with wrong tags is worse than all-dead)
    cp "$ping_file" "${STATE_LAST_PING}.tmp" 2>/dev/null && mv "${STATE_LAST_PING}.tmp" "$STATE_LAST_PING"

    local map_file="${ping_file}.map"
    sl_sel_build_map "$group_tag" "$links_file" "$map_file"
    [ -s "$map_file" ] && sl_hist_record_pings "$ping_file" "$map_file"

    rm -f "$ping_file" "$map_file"
    log "Display ping: $SL_ALIVE_COUNT alive" "debug"
    return 0
}

# Ping only servers belonging to a specific source index (parallel).
# Merges results into STATE_LAST_PING, records history.
# Args: <group_tag> <links_file> <source_idx>
sl_sel_ping_source() {
    local group_tag="$1" links_file="$2" src_idx="$3"
    local tags
    tags="$(sl_clash_get_outbound_tags "$group_tag" 2>/dev/null)"
    [ -z "$tags" ] && return 1

    # Collect tags + urls for this source only
    local ping_file="${STATE_DIR}/ping.src_${src_idx}"
    local urls_file="${ping_file}.urls"
    : > "$urls_file"
    awk -F "$TAB" -v tags="$tags" -v si="$src_idx" '
        BEGIN { nt = split(tags, tarr, "\n"); OFS = "\t" }
        $1 != "" {
            i++
            if ($4 == si && i <= nt) print tarr[i], $1
        }
    ' "$links_file" > "$urls_file"

    [ -s "$urls_file" ] || { rm -f "$urls_file"; return 1; }

    local src_tags=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local tag
        tag="$(printf '%s' "$line" | cut -f1)"
        [ -z "$tag" ] && continue
        src_tags="$src_tags $tag"
    done < "$urls_file"

    # Parallel ping
    # shellcheck disable=SC2086
    sl_clash_ping_tags "$ping_file" "$SL_CFG_PING_TIMEOUT" $src_tags

    # Record history using tag->url map
    local map_file="${ping_file}.map"
    : > "$map_file"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local mtag murl
        mtag="$(printf '%s' "$line" | cut -f1)"
        murl="$(printf '%s' "$line" | cut -f2)"
        printf '%s\t%s\t\t0\n' "$mtag" "$murl" >> "$map_file"
    done < "$urls_file"
    sl_hist_record_pings "$ping_file" "$map_file"
    rm -f "$urls_file" "$map_file"

    # Merge: remove old entries for these tags, add new (atomic write)
    # Skip merge if all dead (sing-box likely reloading, don't zero out others)
    if [ "$SL_ALIVE_COUNT" -eq 0 ] && [ -s "$STATE_LAST_PING" ]; then
        rm -f "$ping_file"
        return 0
    fi
    if [ -s "$STATE_LAST_PING" ]; then
        local merged="${STATE_DIR}/ping_merge.$$"
        awk -F "$TAB" 'NR==FNR{keep[$2]=1; next} !($2 in keep)' \
            "$ping_file" "$STATE_LAST_PING" > "${merged}.tmp" 2>/dev/null
        cat "$ping_file" >> "${merged}.tmp" 2>/dev/null
        mv "${merged}.tmp" "$STATE_LAST_PING" 2>/dev/null
        rm -f "$merged" 2>/dev/null
    else
        cp "$ping_file" "${STATE_LAST_PING}.tmp" 2>/dev/null && mv "${STATE_LAST_PING}.tmp" "$STATE_LAST_PING" 2>/dev/null
    fi
    rm -f "$ping_file"
    return 0
}

# Check if current selection is valid & resolvable.
# Returns 0 if current is valid, 1 otherwise.
sl_sel_current_valid() {
    local links_file="$1" group_tag="$2"
    local cur_url
    cur_url="$(sl_cur_url)"
    [ -z "$cur_url" ] && return 1
    awk -F "$TAB" -v u="$cur_url" '$1==u{f=1} END{exit !f}' "$links_file" 2>/dev/null || return 1
    local tag
    tag="$(sl_sel_resolve_current "$links_file" "$group_tag" "$cur_url")"
    [ -n "$tag" ]
}

# Write parsed links into Podkop's selector_proxy_links and reload.
# Args: <links_file>
# Returns 0 on success, 1 on failure.
sl_sel_apply_podkop() {
    local links_file="$1" section="$SL_CFG_TARGET_SECTION"

    [ -x "$PODKOP_BIN" ] || { log "Podkop binary not found at $PODKOP_BIN" "error"; return 1; }

    uci -q set "podkop.$section.proxy_config_type=selector" 2>/dev/null
    uci -q delete "podkop.$section.selector_proxy_links" 2>/dev/null

    # Batch all add_list calls via uci batch (single transaction)
    # Escape single quotes in URLs for uci batch safety
    local url
    {
        sl_links_urls "$links_file" | while IFS= read -r url; do
            [ -z "$url" ] && continue
            local esc_url
            esc_url="$(printf '%s' "$url" | sed "s/'/'\\\\''/g")"
            printf "add_list podkop.%s.selector_proxy_links='%s'\n" "$section" "$esc_url"
        done
    } | uci -q batch 2>/dev/null

    uci -q commit podkop 2>/dev/null || { log "Failed to commit podkop UCI" "error"; return 1; }

    log "Reloading Podkop to apply $SL_FETCH_COUNT links" "info"
    if ! /etc/init.d/podkop reload >/dev/null 2>&1; then
        "$PODKOP_BIN" reload >/dev/null 2>&1 || {
            log "Podkop reload failed, trying restart" "warn"
            /etc/init.d/podkop restart >/dev/null 2>&1 || true
        }
    fi

    # Clear stale ping data — tags may change after reload
    rm -f "$STATE_LAST_PING" 2>/dev/null

    sl_clash_wait_ready || { log "Clash API not ready after reload" "error"; return 1; }
    sl_clash_redetect

    # After reload sing-box resets selector to first outbound.
    # Re-point to current if still present.
    local cur_url cur_tag group_tag
    cur_url="$(sl_cur_url)"
    if [ -n "$cur_url" ]; then
        group_tag="$(sl_clash_group_tag "$section")"
        cur_tag="$(sl_sel_resolve_current "$links_file" "$group_tag" "$cur_url")"
        [ -n "$cur_tag" ] && sl_clash_set_group "$group_tag" "$cur_tag" 2>/dev/null \
            && log "Re-pointed group to current after reload: $cur_tag" "debug"
    fi

    return 0
}

# Check if podkop UCI links match links_file (by URL set, not just count).
# Returns 0 if in sync, 1 if mismatch (needs apply).
sl_sel_podkop_in_sync() {
    local links_file="$1" section="$SL_CFG_TARGET_SECTION"
    local uci_urls file_urls
    uci_urls="$(uci -q get "podkop.$section.selector_proxy_links" 2>/dev/null | tr ' ' '\n' | grep '://' | sort -u)"
    file_urls="$(sl_links_urls "$links_file" | sort -u)"
    [ "$uci_urls" = "$file_urls" ]
}

# Refresh subscription and apply to Podkop if the link set changed.
# Args: <work_file> [changed_hashes]
# Sets: SL_SYNC_RELOADED (1 if podkop was reloaded)
# Returns: 0=ok (applied or unchanged), 1=fetch failed, 2=apply failed/locked
sl_sel_sync() {
    local work_file="$1" changed="$2"
    SL_SYNC_RELOADED=0

    # Atomic lock — mkdir is atomic on all filesystems
    if ! mkdir "${STATE_DIR}/sync.lock" 2>/dev/null; then
        local lock_pid
        lock_pid=$(cat "${STATE_DIR}/sync.lock/pid" 2>/dev/null)
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            log "Removing stale sync lock (pid=$lock_pid)" "warn"
            rm -rf "${STATE_DIR}/sync.lock" 2>/dev/null
            mkdir "${STATE_DIR}/sync.lock" 2>/dev/null || return 2
        else
            log "Sync locked by pid=$lock_pid, skipping" "debug"
            return 2
        fi
    fi
    echo $$ > "${STATE_DIR}/sync.lock/pid"

    if ! sl_sub_rebuild "$work_file" "$changed"; then
        rm -rf "${STATE_DIR}/sync.lock" 2>/dev/null
        return 1
    fi

    local apply_rc=0
    if sl_links_changed "$work_file" || [ ! -f "$STATE_LINKS_CACHE" ] || ! sl_sel_podkop_in_sync "$work_file"; then
        log "Link set changed ($SL_FETCH_COUNT links), applying to Podkop" "info"
        if sl_sel_apply_podkop "$work_file"; then
            SL_SYNC_RELOADED=1
        else
            apply_rc=2
        fi
    fi

    sl_links_save_cache "$work_file"
    cp "$work_file" "${STATE_LINKS_FULL}.tmp" 2>/dev/null && mv "${STATE_LINKS_FULL}.tmp" "$STATE_LINKS_FULL"
    sl_mark_update
    rm -rf "${STATE_DIR}/sync.lock" 2>/dev/null
    return $apply_rc
}
