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
    sl_tags_cache_save "$group_tag" "$links_file" "$tags" 2>/dev/null || true

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
    tags="$(sl_tags_get_valid "$group_tag" "$links_file" 2>/dev/null)" || { echo ""; return; }

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

# Pick a preferred URL only if it is healthy in the full-scan result.
# Args: <ping_file> <map_file> <preferred_url> <max_ping>
sl_sel_pick_preferred() {
    local ping_file="$1" map_file="$2" preferred_url="$3" max_ping="$4"
    [ -n "$preferred_url" ] || return 1

    awk -F "$TAB" -v map_file="$map_file" -v preferred_url="$preferred_url" -v max_ping="$max_ping" '
        BEGIN {
            while ((getline line < map_file) > 0) {
                split(line, a, "\t")
                tag_url[a[1]] = a[2]
            }
            close(map_file)
            max = max_ping + 0
        }
        $1 ~ /^[0-9]+$/ {
            tag = $2
            lat = $1 + 0
            if (tag_url[tag] == preferred_url && (max <= 0 || lat <= max)) {
                print tag
                exit
            }
        }
    ' "$ping_file" 2>/dev/null
}

# Pick the best healthy tag. With source priority enabled, choose the first
# source that has healthy servers, then the lowest latency inside that source.
# Args: <ping_file> <map_file> <use_priority> <max_ping>
# Echoes "<tag>" (best tag, or empty if none healthy).
sl_sel_pick_best() {
    local ping_file="$1" map_file="$2" use_priority="$3" max_ping="$4"

    awk -F "$TAB" -v map_file="$map_file" -v use_priority="$use_priority" -v max_ping="$max_ping" '
        BEGIN {
            while ((getline line < map_file) > 0) {
                split(line, a, "\t")
                tag_src[a[1]] = a[5] + 0
            }
            close(map_file)
            max = max_ping + 0
            best_src = 999999
            best_lat = 999999
            best_tag = ""
        }
        $1 ~ /^[0-9]+$/ {
            tag = $2
            lat = $1 + 0
            src_idx = tag_src[tag]
            if (max > 0 && lat > max) next

            if (use_priority == "1") {
                if (src_idx < best_src || (src_idx == best_src && lat < best_lat)) {
                    best_src = src_idx
                    best_lat = lat
                    best_tag = tag
                }
            } else if (lat < best_lat) {
                best_lat = lat
                best_tag = tag
            }
        }
        END {
            if (best_tag != "") print best_tag
        }
    ' "$ping_file" 2>/dev/null
}

sl_sel_count_healthy() {
    local ping_file="$1" max_ping="$2"
    awk -F "$TAB" -v max_ping="$max_ping" '
        BEGIN { max = max_ping + 0; healthy = 0 }
        $1 ~ /^[0-9]+$/ {
            lat = $1 + 0
            if (max <= 0 || lat <= max) healthy++
        }
        END { print healthy }
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

# Ping all outbounds, record history, pick a healthy server, select it.
# Args: <group_tag> <links_file> [preferred_url] [ping_out_file]
# preferred_url is kept only if it is healthy (current recovery / reboot restore).
# Returns 1 if no healthy server exists.
sl_sel_ping_all() {
    local group_tag="$1" links_file="$2" preferred_url="${3:-}"
    local ping_file="${4:-${STATE_DIR}/ping.$$}"
    local timeout="$SL_CFG_PING_TIMEOUT"

    if ! sl_clash_ping_group "$group_tag" "$ping_file" "$timeout"; then
        log "Could not ping group '$group_tag'" "warn"
        rm -f "$ping_file"
        return 1
    fi

    cp "$ping_file" "${STATE_LAST_PING}.$$" 2>/dev/null && mv "${STATE_LAST_PING}.$$" "$STATE_LAST_PING"
    local healthy_count
    healthy_count="$(sl_sel_count_healthy "$ping_file" "$SL_CFG_MAX_PING")"
    log "Ping all: $SL_ALIVE_COUNT responded, $healthy_count healthy (threshold ${SL_CFG_MAX_PING}ms)" "debug"

    if [ "$SL_ALIVE_COUNT" -le 0 ]; then
        rm -f "$ping_file"
        return 1
    fi

    local map_file="${ping_file}.map"
    sl_sel_build_map "$group_tag" "$links_file" "$map_file"
    [ -s "$map_file" ] || { rm -f "$ping_file"; return 1; }

    # Record history for all tested servers (single unified call)
    sl_hist_record_pings "$ping_file" "$map_file"

    # Keep current/last selection if it recovered and is healthy.
    local cur_url tag
    cur_url="$(sl_cur_url)"
    [ -z "$cur_url" ] && cur_url="$preferred_url"
    tag="$(sl_sel_pick_preferred "$ping_file" "$map_file" "$cur_url" "$SL_CFG_MAX_PING")"

    # Otherwise choose the best healthy replacement.
    [ -z "$tag" ] && tag="$(sl_sel_pick_best "$ping_file" "$map_file" "$SL_CFG_USE_PRIORITY" "$SL_CFG_MAX_PING")"

    rm -f "$ping_file"
    [ -z "$tag" ] && {
        log "No healthy servers found (threshold ${SL_CFG_MAX_PING}ms)" "warn"
        rm -f "$map_file"
        return 1
    }

    sl_sel_select "$group_tag" "$links_file" "$tag" "$map_file"
    local rc=$?
    rm -f "$map_file"
    return $rc
}

# Background Stats ping of ALL servers for dashboard/history only.
# Saves results to STATE_LAST_PING and records history, does NOT switch.
# Args: <group_tag> <links_file>
sl_sel_stats_ping() {
    local group_tag="$1" links_file="$2"
    local ping_file="${STATE_DIR}/ping.stats.$$"

    # Batched parallel ping (sequential was too slow through NAT)
    if ! sl_clash_ping_group "$group_tag" "$ping_file" "$SL_CFG_PING_TIMEOUT" 0; then
        log "Stats ping: could not ping group" "debug"
        rm -f "$ping_file"
        return 1
    fi

    # Always update STATE_LAST_PING (stale data with wrong tags is worse than all-dead)
    cp "$ping_file" "${STATE_LAST_PING}.$$" 2>/dev/null && mv "${STATE_LAST_PING}.$$" "$STATE_LAST_PING"

    local map_file="${ping_file}.map"
    sl_sel_build_map "$group_tag" "$links_file" "$map_file"
    [ -s "$map_file" ] && sl_hist_record_pings "$ping_file" "$map_file"

    rm -f "$ping_file" "$map_file"
    return 0
}

# Ping only servers belonging to a specific source index (parallel).
# Merges results into STATE_LAST_PING, records history.
# Args: <group_tag> <links_file> <source_idx>
sl_sel_ping_source() {
    local group_tag="$1" links_file="$2" src_idx="$3"
    local tags
    tags="$(sl_tags_get_valid "$group_tag" "$links_file" 2>/dev/null)" || return 1

    # Collect tags + urls for this source only
    local ping_file="${STATE_DIR}/ping.src_${src_idx}.$$"
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

    local src_tags_file="${ping_file}.tags"
    : > "$src_tags_file"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local tag
        tag="$(printf '%s' "$line" | cut -f1)"
        [ -z "$tag" ] && continue
        printf '%s\n' "$tag" >> "$src_tags_file"
    done < "$urls_file"

    # Parallel ping
    sl_clash_ping_tags_file "$ping_file" "$SL_CFG_PING_TIMEOUT" "$src_tags_file"

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
    rm -f "$urls_file" "$src_tags_file" "$map_file"

    # Merge: remove old entries for these tags, add new (atomic write)
    # Skip merge if all dead (sing-box likely reloading, don't zero out others)
    if [ "$SL_ALIVE_COUNT" -eq 0 ] && [ -s "$STATE_LAST_PING" ]; then
        rm -f "$ping_file"
        return 0
    fi
    if [ -s "$STATE_LAST_PING" ]; then
        local merged="${STATE_DIR}/ping_merge.$$"
        local merged_tmp="${merged}.tmp"
        awk -F "$TAB" 'NR==FNR{keep[$2]=1; next} !($2 in keep)' \
            "$ping_file" "$STATE_LAST_PING" > "$merged_tmp" 2>/dev/null
        cat "$ping_file" >> "$merged_tmp" 2>/dev/null
        mv "$merged_tmp" "$STATE_LAST_PING" 2>/dev/null
        rm -f "$merged" "$merged_tmp" 2>/dev/null
    else
        cp "$ping_file" "${STATE_LAST_PING}.$$" 2>/dev/null && mv "${STATE_LAST_PING}.$$" "$STATE_LAST_PING" 2>/dev/null
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

sl_sel_podkop_urls() {
    uci -q get "podkop.$1.selector_proxy_links" 2>/dev/null | tr ' ' '\n' | grep '://'
}

sl_sel_state_urls() {
    local file="$1"
    [ -s "$file" ] || return 1
    if grep -q "$TAB" "$file" 2>/dev/null; then
        cut -f1 "$file" 2>/dev/null
    else
        cat "$file" 2>/dev/null
    fi
}

sl_sel_urls_same_set() {
    [ "$(printf '%s\n' "$1" | sort -u)" = "$(printf '%s\n' "$2" | sort -u)" ]
}

sl_sel_known_smartlink_urls() {
    local file
    for file in "$STATE_LINKS_FULL" "$STATE_LINKS_EXCLUDED" "$STATE_LINKS_CACHE"; do
        [ -s "$file" ] || continue
        sl_sel_state_urls "$file"
    done
    for file in "$STATE_SUB_CACHE"/sub_*; do
        [ -s "$file" ] || continue
        cut -f1 "$file" 2>/dev/null
    done
}

sl_sel_backup_matches_known_state() {
    local old_type old_links known
    old_type="$(uci -q get "$SL_NAME.main.backup_proxy_config_type" 2>/dev/null)"
    [ "$old_type" = "selector" ] || return 1
    old_links="$(uci -q get "$SL_NAME.main.backup_selector_proxy_links" 2>/dev/null | tr ' ' '\n' | grep '://')"
    [ -n "$old_links" ] || return 1
    known="$(sl_sel_known_smartlink_urls | grep '://' | sort -u)"
    [ -n "$known" ] || return 1
    sl_sel_urls_same_set "$old_links" "$known"
}

sl_sel_sanitize_legacy_backup() {
    local section="$1"
    [ "$(uci -q get "$SL_NAME.main.managed_section" 2>/dev/null)" = "$section" ] || return 1
    sl_sel_backup_matches_known_state || return 1
    uci -q delete "$SL_NAME.main.backup_proxy_config_type" 2>/dev/null
    uci -q delete "$SL_NAME.main.backup_selector_proxy_links" 2>/dev/null
    uci -q commit "$SL_NAME" 2>/dev/null || return 1
    log "Cleared legacy SmartLink selector snapshot for section '$section'" "warn"
    return 0
}

sl_sel_legacy_state_matches() {
    local section="$1" current file urls
    [ "$(uci -q get "podkop.$section.proxy_config_type" 2>/dev/null)" = "selector" ] || return 1
    current="$(sl_sel_podkop_urls "$section")"
    [ -n "$current" ] || return 1

    for file in "$STATE_LINKS_FULL" "$STATE_LINKS_CACHE"; do
        [ -s "$file" ] || continue
        urls="$(sl_sel_state_urls "$file")"
        [ -n "$urls" ] || continue
        [ "$current" = "$urls" ] && return 0
        sl_sel_urls_same_set "$current" "$urls" && return 0
    done
    return 1
}

sl_sel_adopt_legacy_podkop() {
    local section="$1"
    sl_sel_legacy_state_matches "$section" || return 1
    uci -q delete "$SL_NAME.main.backup_proxy_config_type" 2>/dev/null
    uci -q delete "$SL_NAME.main.backup_selector_proxy_links" 2>/dev/null
    uci -q set "$SL_NAME.main.managed_section=$section" 2>/dev/null || return 1
    uci -q commit "$SL_NAME" 2>/dev/null || return 1
    log "Adopted legacy SmartLink-managed Podkop section '$section'" "info"
    return 0
}

sl_sel_backup_podkop() {
    local section="$1"
    local managed
    managed="$(uci -q get "$SL_NAME.main.managed_section" 2>/dev/null)"
    if [ "$managed" = "$section" ]; then
        sl_sel_sanitize_legacy_backup "$section" >/dev/null 2>&1 || true
        return 0
    fi
    if [ -n "$managed" ] && [ "$managed" != "$section" ]; then
        sl_sel_restore_podkop "$managed" || return 1
    fi

    sl_sel_adopt_legacy_podkop "$section" && return 0

    uci -q delete "$SL_NAME.main.backup_selector_proxy_links" 2>/dev/null
    uci -q set "$SL_NAME.main.managed_section=$section" 2>/dev/null
    uci -q set "$SL_NAME.main.backup_proxy_config_type=$(uci -q get "podkop.$section.proxy_config_type" 2>/dev/null)" 2>/dev/null

    local link
    uci -q get "podkop.$section.selector_proxy_links" 2>/dev/null | tr ' ' '\n' | while IFS= read -r link; do
        [ -n "$link" ] && uci -q add_list "$SL_NAME.main.backup_selector_proxy_links=$link" 2>/dev/null
    done
    uci -q commit "$SL_NAME" 2>/dev/null
}

sl_sel_write_podkop_config() {
    local section="$1" proxy_type="$2" links="$3"
    local batch_file="${STATE_DIR}/podkop_config.$$"

    uci -q delete "podkop.$section.selector_proxy_links" 2>/dev/null || true
    [ -n "$proxy_type" ] || uci -q delete "podkop.$section.proxy_config_type" 2>/dev/null || true
    {
        if [ -n "$proxy_type" ]; then
            local esc_type
            esc_type="$(printf '%s' "$proxy_type" | sed "s/'/'\\\\''/g")"
            printf "set podkop.%s.proxy_config_type='%s'\n" "$section" "$esc_type"
        fi
        printf '%s\n' "$links" | tr ' ' '\n' | while IFS= read -r url; do
            [ -n "$url" ] || continue
            local esc_url
            esc_url="$(printf '%s' "$url" | sed "s/'/'\\\\''/g")"
            printf "add_list podkop.%s.selector_proxy_links='%s'\n" "$section" "$esc_url"
        done
    } > "$batch_file"

    uci -q batch < "$batch_file" 2>/dev/null || { rm -f "$batch_file"; return 1; }
    rm -f "$batch_file"
    uci -q commit podkop 2>/dev/null
}

sl_sel_restore_podkop_snapshot() {
    sl_sel_write_podkop_config "$1" "$2" "$3"
}

# Write parsed links into Podkop's selector_proxy_links and reload.
# Args: <links_file>
# Returns 0 on success, 1 on failure.
sl_sel_apply_podkop() {
    local links_file="$1" section="$SL_CFG_TARGET_SECTION"

    [ -x "$PODKOP_BIN" ] || { log "Podkop binary not found at $PODKOP_BIN" "error"; return 1; }

    sl_sel_backup_podkop "$section" || {
        log "Failed to backup Podkop section '$section'" "error"
        return 1
    }

    local prev_type prev_links
    prev_type="$(uci -q get "podkop.$section.proxy_config_type" 2>/dev/null)"
    prev_links="$(uci -q get "podkop.$section.selector_proxy_links" 2>/dev/null)"

    # Batch all add_list calls via uci batch (single transaction)
    # Escape single quotes in URLs for uci batch safety
    local url batch_file="${STATE_DIR}/podkop_uci.$$"
    uci -q delete "podkop.$section.selector_proxy_links" 2>/dev/null || true
    {
        printf "set podkop.%s.proxy_config_type='selector'\n" "$section"
        sl_links_urls "$links_file" | while IFS= read -r url; do
            [ -z "$url" ] && continue
            local esc_url
            esc_url="$(printf '%s' "$url" | sed "s/'/'\\\\''/g")"
            printf "add_list podkop.%s.selector_proxy_links='%s'\n" "$section" "$esc_url"
        done
    } > "$batch_file"

    if ! uci -q batch < "$batch_file" 2>/dev/null; then
        rm -f "$batch_file"
        log "Failed to update podkop UCI selector links" "error"
        sl_sel_restore_podkop_snapshot "$section" "$prev_type" "$prev_links" >/dev/null 2>&1 || true
        return 1
    fi
    rm -f "$batch_file"

    local expected actual
    expected="$(grep -c . "$links_file" 2>/dev/null || echo 0)"
    actual="$(uci -q get "podkop.$section.selector_proxy_links" 2>/dev/null | tr ' ' '\n' | grep -c . 2>/dev/null)"
    case "$expected" in *[!0-9]*) expected=0 ;; esac
    case "$actual" in *[!0-9]*) actual=0 ;; esac
    if [ "$expected" -ne "$actual" ]; then
        log "Podkop UCI selector link count mismatch ($actual/$expected)" "error"
        sl_sel_restore_podkop_snapshot "$section" "$prev_type" "$prev_links" >/dev/null 2>&1 || true
        return 1
    fi

    uci -q commit podkop 2>/dev/null || {
        log "Failed to commit podkop UCI" "error"
        sl_sel_restore_podkop_snapshot "$section" "$prev_type" "$prev_links" >/dev/null 2>&1 || true
        return 1
    }

    log "Reloading Podkop to apply $SL_FETCH_COUNT links" "info"
    if ! /etc/init.d/podkop reload >/dev/null 2>&1; then
        "$PODKOP_BIN" reload >/dev/null 2>&1 || {
            log "Podkop reload failed, trying restart" "warn"
            /etc/init.d/podkop restart >/dev/null 2>&1 || true
        }
    fi

    # Clear stale ping data — tags may change after reload
    rm -f "$STATE_LAST_PING" 2>/dev/null
    sl_tags_cache_clear

    sl_clash_wait_ready || {
        log "Clash API not ready after reload, restoring previous Podkop config" "error"
        sl_sel_restore_podkop_snapshot "$section" "$prev_type" "$prev_links" >/dev/null 2>&1 || true
        /etc/init.d/podkop reload >/dev/null 2>&1 || "$PODKOP_BIN" reload >/dev/null 2>&1 || true
        return 1
    }
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

# Restore the Podkop section that SmartLink previously took over.
sl_sel_restore_podkop() {
    local section="${1:-$(uci -q get "$SL_NAME.main.managed_section" 2>/dev/null)}"
    [ -n "$section" ] || return 0
    sl_sel_sanitize_legacy_backup "$section" >/dev/null 2>&1 || true

    local old_type old_links
    old_type="$(uci -q get "$SL_NAME.main.backup_proxy_config_type" 2>/dev/null)"
    old_links="$(uci -q get "$SL_NAME.main.backup_selector_proxy_links" 2>/dev/null)"
    sl_sel_write_podkop_config "$section" "$old_type" "$(printf '%s' "$old_links" | tr ' ' '\n')" || return 1

    uci -q delete "$SL_NAME.main.managed_section" 2>/dev/null
    uci -q delete "$SL_NAME.main.backup_proxy_config_type" 2>/dev/null
    uci -q delete "$SL_NAME.main.backup_selector_proxy_links" 2>/dev/null
    uci -q commit "$SL_NAME" 2>/dev/null
    log "Restored Podkop section '$section' after SmartLink management" "info"
    return 0
}

sl_sel_release_podkop() {
    local section="${1:-$SL_CFG_TARGET_SECTION}"
    local managed old_type old_links
    managed="$(uci -q get "$SL_NAME.main.managed_section" 2>/dev/null)"

    [ -n "$managed" ] || return 0
    sl_sel_sanitize_legacy_backup "$managed" >/dev/null 2>&1 || true
    old_type="$(uci -q get "$SL_NAME.main.backup_proxy_config_type" 2>/dev/null)"
    old_links="$(uci -q get "$SL_NAME.main.backup_selector_proxy_links" 2>/dev/null)"

    if sl_sel_restore_podkop "$managed" >/dev/null 2>&1; then
        if [ -n "$old_type" ] || [ -n "$old_links" ]; then
            /etc/init.d/podkop reload >/dev/null 2>&1 || "$PODKOP_BIN" reload >/dev/null 2>&1 || true
        fi
        return 0
    fi

    sl_sel_clear_podkop "$section" >/dev/null 2>&1
}

# Remove SmartLink-managed selector links from Podkop persistent config.
# Does not reload Podkop: an empty selector section is not a valid runtime config.
sl_sel_clear_podkop() {
    local section="${1:-$SL_CFG_TARGET_SECTION}"
    local managed
    managed="$(uci -q get "$SL_NAME.main.managed_section" 2>/dev/null)"
    [ -n "$managed" ] && [ "$managed" != "$section" ] && return 0
    uci -q delete "podkop.$section.selector_proxy_links" 2>/dev/null
    if [ "$(uci -q get "podkop.$section.proxy_config_type" 2>/dev/null)" = "selector" ]; then
        uci -q delete "podkop.$section.proxy_config_type" 2>/dev/null
    fi
    uci -q commit podkop 2>/dev/null || {
        log "Failed to clear Podkop selector links" "warn"
        return 1
    }
    uci -q delete "$SL_NAME.main.managed_section" 2>/dev/null
    uci -q delete "$SL_NAME.main.backup_proxy_config_type" 2>/dev/null
    uci -q delete "$SL_NAME.main.backup_selector_proxy_links" 2>/dev/null
    uci -q commit "$SL_NAME" 2>/dev/null || true
    log "Cleared Podkop selector links for section '$section'" "info"
    return 0
}

# Check if podkop UCI links match links_file in the same order.
# Returns 0 if in sync, 1 if mismatch (needs apply).
sl_sel_podkop_in_sync() {
    local links_file="$1" section="$SL_CFG_TARGET_SECTION"
    [ "$(uci -q get "podkop.$section.proxy_config_type" 2>/dev/null)" = "selector" ] || return 1

    local uci_urls file_urls group_tag tags tag_count link_count
    uci_urls="$(uci -q get "podkop.$section.selector_proxy_links" 2>/dev/null | tr ' ' '\n' | grep '://')"
    file_urls="$(sl_links_urls "$links_file")"
    [ "$uci_urls" = "$file_urls" ] || return 1

    group_tag="$(sl_clash_group_tag "$section")"
    tags="$(sl_clash_get_outbound_tags "$group_tag" 2>/dev/null)" || return 1
    [ -n "$tags" ] || return 1
    tag_count="$(printf '%s\n' "$tags" | grep -c . 2>/dev/null || echo 0)"
    link_count="$(grep -c . "$links_file" 2>/dev/null || echo 0)"
    case "$tag_count" in *[!0-9]*) tag_count=0 ;; esac
    case "$link_count" in *[!0-9]*) link_count=0 ;; esac
    [ "$tag_count" -eq "$link_count" ]
}

sl_sel_publish_no_active() {
    local work_file="$1"
    local tmp

    tmp="${STATE_LINKS_FULL}.$$"
    : > "$tmp" && mv "$tmp" "$STATE_LINKS_FULL"

    if [ -f "${work_file}.excluded" ]; then
        cp "${work_file}.excluded" "${STATE_LINKS_EXCLUDED}.$$" 2>/dev/null \
            && mv "${STATE_LINKS_EXCLUDED}.$$" "$STATE_LINKS_EXCLUDED"
    else
        tmp="${STATE_LINKS_EXCLUDED}.$$"
        : > "$tmp" && mv "$tmp" "$STATE_LINKS_EXCLUDED"
    fi

    tmp="${STATE_LINKS_CACHE}.$$"
    : > "$tmp" && mv "$tmp" "$STATE_LINKS_CACHE"
    rm -f "$STATE_LAST_PING" 2>/dev/null
    sl_tags_cache_clear
    sl_cur_clear
    sl_mark_update

    sl_sel_release_podkop "$SL_CFG_TARGET_SECTION" >/dev/null 2>&1 || true
}

# Refresh subscription and apply to Podkop if the link set changed.
# Args: <work_file> [changed_hashes]
# Sets: SL_SYNC_RELOADED (1 if podkop was reloaded)
# Returns: 0=ok (applied or unchanged), 1=fetch failed, 2=apply failed/locked
sl_sel_sync() {
    local work_file="$1" changed="$2"
    SL_SYNC_RELOADED=0

    local lock_token
    lock_token="$(sl_lock_acquire "$STATE_SYNC_LOCK" 0)" || {
        log "Sync locked, skipping" "debug"
        return 2
    }
    SL_SYNC_LOCK_TOKEN="$lock_token"

    if ! sl_sub_rebuild "$work_file" "$changed"; then
        if [ "$(sl_safe_num "$SL_FETCH_EMPTY_ACTIVE")" -eq 1 ]; then
            log "No active SmartLink servers; publishing excluded-only state" "warn"
            sl_sel_publish_no_active "$work_file"
            sl_lock_release "$STATE_SYNC_LOCK" "$lock_token"
            SL_SYNC_LOCK_TOKEN=""
            return 0
        fi
        sl_lock_release "$STATE_SYNC_LOCK" "$lock_token"
        SL_SYNC_LOCK_TOKEN=""
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

    if [ "$apply_rc" -ne 0 ]; then
        sl_lock_release "$STATE_SYNC_LOCK" "$lock_token"
        SL_SYNC_LOCK_TOKEN=""
        return $apply_rc
    fi

    sl_links_save_cache "$work_file"
    cp "$work_file" "${STATE_LINKS_FULL}.$$" 2>/dev/null && mv "${STATE_LINKS_FULL}.$$" "$STATE_LINKS_FULL"
    if [ -f "${work_file}.excluded" ] && cp "${work_file}.excluded" "${STATE_LINKS_EXCLUDED}.$$" 2>/dev/null; then
        mv "${STATE_LINKS_EXCLUDED}.$$" "$STATE_LINKS_EXCLUDED"
    else
        rm -f "${STATE_LINKS_EXCLUDED}.$$" 2>/dev/null
        : > "${STATE_LINKS_EXCLUDED}.$$" && mv "${STATE_LINKS_EXCLUDED}.$$" "$STATE_LINKS_EXCLUDED"
    fi
    sl_mark_update
    sl_lock_release "$STATE_SYNC_LOCK" "$lock_token"
    SL_SYNC_LOCK_TOKEN=""
    return $apply_rc
}
