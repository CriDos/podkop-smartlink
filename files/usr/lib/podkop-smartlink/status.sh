# Status JSON builder for podkop-smartlink (dashboard snapshot)

# Current selection helpers (keyed by URL, stable across reloads).
sl_cur_url()   { [ -f "$STATE_CURRENT" ] && cut -f1 "$STATE_CURRENT" 2>/dev/null || echo ""; }

sl_cur_set() {
    local url="$1" tag="$2" title="$3"
    printf '%s\t%s\t%s\t%s\n' "$url" "$tag" "$title" "$(date +%s)" > "${STATE_CURRENT}.tmp"
    mv "${STATE_CURRENT}.tmp" "$STATE_CURRENT"
}

# Persist current selection to UCI (for cross-reboot restore).
# Called once on daemon shutdown, not on every selection.
sl_cur_persist() {
    local url
    url="$(sl_cur_url)"
    [ -z "$url" ] && return 0
    uci -q set "$SL_NAME.main.last_selected=$url" 2>/dev/null
    uci -q commit "$SL_NAME" 2>/dev/null
}

sl_cur_update_tag() {
    [ -f "$STATE_CURRENT" ] || return 1
    local tag="$1"
    awk -F "$TAB" -v t="$tag" 'BEGIN{OFS="\t"} {$2=t; print; exit}' \
        "$STATE_CURRENT" > "${STATE_CURRENT}.tmp" && mv "${STATE_CURRENT}.tmp" "$STATE_CURRENT"
}

sl_cur_clear() {
    rm -f "$STATE_CURRENT" "${STATE_CURRENT}.tmp"
}

# Links cache (for diff detection).
sl_links_save_cache() { sl_links_urls "$1" | sort -u > "${STATE_LINKS_CACHE}.tmp" && mv "${STATE_LINKS_CACHE}.tmp" "$STATE_LINKS_CACHE"; }
sl_links_changed() {
    local new_set
    new_set="$(sl_links_urls "$1" | sort -u)"
    [ -f "$STATE_LINKS_CACHE" ] || return 1
    [ "$new_set" != "$(cat "$STATE_LINKS_CACHE")" ]
}

# Update timestamps.
sl_mark_update() { date +%s > "$STATE_LAST_UPDATE"; }
sl_last_update() { [ -f "$STATE_LAST_UPDATE" ] && cat "$STATE_LAST_UPDATE" || echo 0; }

# Build status.json and print it.
# Args: <links_file> <group_tag> [ping_file]
# ping_file format: "<latency>\t<tag>" per line (optional, falls back to STATE_LAST_PING)
sl_status_build() {
    local links_file="$1" group_tag="$2" ping_file="$3"

    [ -z "$ping_file" ] && [ -s "$STATE_LAST_PING" ] && ping_file="$STATE_LAST_PING"

    local target cur_url cur_tag cur_title now next interval_sec
    target="$SL_CFG_TARGET_SECTION"
    cur_url="" cur_tag="" cur_title=""
    if [ -f "$STATE_CURRENT" ]; then
        cur_url="$(cut -f1 "$STATE_CURRENT" 2>/dev/null)"
        cur_tag="$(cut -f2 "$STATE_CURRENT" 2>/dev/null)"
        cur_title="$(cut -f3 "$STATE_CURRENT" 2>/dev/null)"
    fi
    now="$(date +%s)"
    interval_sec="$(sl_interval_to_sec "$SL_CFG_UPDATE_INTERVAL")"
    next=$(( $(sl_safe_num "$(sl_last_update)") + interval_sec ))

    # Precompute tags
    local tags=""
    [ -n "$group_tag" ] && tags="$(sl_clash_get_outbound_tags "$group_tag" 2>/dev/null)"

    local stats_cache="${STATE_DIR}/stats.$$"
    local keymap="${STATE_DIR}/keymap.$$"
    local tags_file="${STATE_DIR}/tags.$$"
    local data_file="${STATE_DIR}/status_data.$$"

    sl_hist_precompute_all "$stats_cache"

    : > "$keymap"
    local url key
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        url="$(printf '%s' "$line" | cut -f1)"
        [ -z "$url" ] && continue
        key="$(sl_hist_key "$url")"
        printf '%s\t%s\n' "$key" "$url" >> "$keymap"
    done < "$links_file"

    printf '%s\n' "$tags" > "$tags_file"

    local ping_arg="$ping_file"
    [ -z "$ping_arg" ] && ping_arg="/dev/null"

    awk -F "$TAB" -v sc="$stats_cache" -v km="$keymap" -v tf="$tags_file" \
        -v pa="$ping_arg" -v cur_url="$cur_url" '
        BEGIN {
            while ((getline line < sc) > 0) {
                n = split(line, a, "\t")
                stats[a[1]] = a[2] "\t" a[3] "\t" a[4]
            }
            close(sc)
            while ((getline line < km) > 0) {
                split(line, a, "\t")
                keys[a[2]] = a[1]
            }
            close(km)
            tn = 0
            while ((getline line < tf) > 0) { tn++; tags[tn] = line }
            close(tf)
            while ((getline line < pa) > 0) {
                split(line, a, "\t")
                ping[a[2]] = a[1]
            }
            close(pa)
            i = 0
        }
        NF >= 3 {
            i++
            url = $1; title = $2; src_idx = (NF >= 4 ? $4 : "0")
            tag = tags[i]
            lat = (tag in ping ? ping[tag] : "")
            alive = (lat != "" && lat != "0" ? "true" : "false")
            sel = (url == cur_url ? "true" : "false")
            avail = "0"; stab = "0"; total = "0"
            if (url in keys) {
                k = keys[url]
                if (k in stats) {
                    split(stats[k], sa, "\t")
                    avail = sa[1]; stab = sa[2]; total = sa[3]
                }
            }
            print tag "\t" url "\t" title "\t" src_idx "\t" (lat == "" ? "0" : lat) "\t" alive "\t" sel "\t" avail "\t" stab "\t" total "\t" i
        }
    ' "$links_file" > "$data_file" 2>/dev/null

    rm -f "$tags_file" "$stats_cache" "$keymap"

    local proxies_json="[]"
    if [ -s "$data_file" ]; then
        proxies_json="$(jq -R -s '
            split("\n") | map(select(length > 0)) | map(
                split("\t") | {
                    tag: .[0], url: .[1], title: .[2],
                    source: (.[3] | tonumber), ping: (.[4] | tonumber),
                    alive: (.[5] == "true"), selected: (.[6] == "true"),
                    availability: (.[7] | tonumber), stability: (.[8] | tonumber),
                    checks: (.[9] | tonumber), index: (.[10] | tonumber)
                }
            )
        ' "$data_file")"
    fi
    rm -f "$data_file"

    local cur_obj="null"
    [ -n "$cur_url" ] && cur_obj="$(jq -c -n \
        --arg tag "$cur_tag" --arg url "$cur_url" --arg title "$cur_title" \
        '{tag:$tag,url:$url,title:$title}')"

    local refreshing="false"
    [ -f "${STATE_DIR}/refreshing" ] && refreshing="true"

    jq -n -c \
        --arg mode "auto" \
        --arg target "$target" --arg group "$group_tag" --argjson current "$cur_obj" \
        --argjson proxies "$proxies_json" --argjson now "$now" --argjson next "$next" \
        --argjson last_update "$(sl_safe_num "$(sl_last_update)")" \
        --argjson refreshing "$refreshing" \
        '{mode:$mode,target_section:$target,group_tag:$group,
          current:$current,proxies:$proxies,now:$now,next_update:$next,
          last_update:$last_update,refreshing:$refreshing}' > "${STATE_STATUS}.tmp"

    mv "${STATE_STATUS}.tmp" "$STATE_STATUS"
    cat "$STATE_STATUS"
}
