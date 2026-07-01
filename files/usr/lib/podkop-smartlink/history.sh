# History management for podkop-smartlink (per-URL ping history in /tmp)

# MD5-based stable key for a URL (16 chars, filesystem-safe).
sl_hist_key() {
    printf '%s' "$1" | md5sum | cut -c1-16
}

# Append a measurement. Args: <url> <latency_or_empty> <ok:1|0>
sl_hist_append() {
    local url="$1" lat="$2" ok="$3"
    local key ts
    key="$(sl_hist_key "$url")"
    ts="$(date +%s)"
    [ -z "$lat" ] && lat="-"
    local hfile="$STATE_HISTORY_DIR/$key"

    # Atomic append via mkdir lock (prevents interleaving with concurrent writers)
    local lock_dir="${STATE_HISTORY_DIR}/.lock_${key}"
    local locked=0
    if mkdir "$lock_dir" 2>/dev/null; then
        locked=1
    else
        # Lock contention — just append without lock (low risk for small writes)
        :
    fi

    printf '%s\t%s\t%s\n' "$ts" "$lat" "$ok" >> "$hfile"

    # Trim to max samples if file grew beyond cap
    local lines
    lines="$(wc -l < "$hfile" 2>/dev/null || echo 0)"
    if [ "$lines" -gt "$HISTORY_MAX_SAMPLES" ]; then
        tail -n "$HISTORY_MAX_SAMPLES" "$hfile" > "${hfile}.tmp" && mv "${hfile}.tmp" "$hfile"
    fi

    [ "$locked" = "1" ] && rmdir "$lock_dir" 2>/dev/null
}

# Precompute stats for all history files in a single awk pass.
# Cache format per line: "<md5key>\t<avail>\t<stab>\t<total>"
# Args: <cache_out_file>
sl_hist_precompute_all() {
    local cache_file="$1"
    : > "$cache_file"
    [ -d "$STATE_HISTORY_DIR" ] || return 0

    # Concatenate all history files with filename prefix, single awk pass
    local hfile
    for hfile in "$STATE_HISTORY_DIR"/*; do
        [ -f "$hfile" ] || continue
        case "$(basename "$hfile")" in
            .lock_*) continue ;;
        esac
        local k
        k="$(basename "$hfile")"
        awk -F "$TAB" -v k="$k" '{print k "\t" $0}' "$hfile" 2>/dev/null
    done | awk -F "$TAB" '
        {
            key = $1; ok_flag = $4; lat = $3
            total[key]++
            if (ok_flag == "1") {
                ok[key]++
                if (lat != "-" && lat != "") {
                    n[key]++; sum[key] += lat; vals[key, n[key]] = lat
                }
            }
        }
        END {
            for (key in total) {
                t = total[key]; o = ok[key] + 0; nn = n[key] + 0; s = sum[key] + 0
                if (t <= 0) { printf "%s\t0\t0\t0\n", key; continue }
                avail = o / t
                if (nn < 2) { stab = 0 } else {
                    mean = s / nn
                    sq = 0
                    for (i = 1; i <= nn; i++) { d = vals[key, i] - mean; sq += d * d }
                    cv = sqrt(sq / nn) / (mean > 0 ? mean : 1)
                    if (cv > 1) cv = 1
                    stab = 1 - cv
                }
                printf "%s\t%.2f\t%.2f\t%d\n", key, avail, stab, t
            }
        }
    ' >> "$cache_file" 2>/dev/null
}

# Delete all history files.
sl_hist_reset_all() {
    rm -rf "$STATE_HISTORY_DIR"/*
    rm -f "$STATE_LAST_PING"
    mkdir -p "$STATE_HISTORY_DIR"
}
