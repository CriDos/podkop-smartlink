# Clash API wrapper for podkop-smartlink
# Talks to sing-box experimental clash_api via curl.
# Auto-detects address + optional secret from podkop UCI.

# Detect Clash API base URL and auth. Cached per process.
# Sets: _CLASH_BASE _CLASH_AUTH _CLASH_DETECTED
sl_clash_detect() {
    [ "$_CLASH_DETECTED" = "1" ] && return 0

    local addr=""
    addr="$(uci -q get podkop.settings.service_listen_address 2>/dev/null)"
    [ -z "$addr" ] && addr="$(ubus call network.interface.lan status 2>/dev/null \
        | jq -r '.["ipv4-address"][0].address // empty' 2>/dev/null)"
    [ -z "$addr" ] && addr="127.0.0.1"

    _CLASH_BASE="${addr}:${CLASH_API_PORT}"

    local wan_access secret
    wan_access="$(uci -q get podkop.settings.enable_yacd_wan_access 2>/dev/null)"
    secret="$(uci -q get podkop.settings.yacd_secret_key 2>/dev/null)"
    if [ "$wan_access" = "1" ] && [ -n "$secret" ]; then
        _CLASH_AUTH="Authorization: Bearer $secret"
    else
        _CLASH_AUTH=""
    fi

    _CLASH_DETECTED=1
}

# Force re-detection (e.g. after podkop reload).
sl_clash_redetect() {
    _CLASH_DETECTED=0
    sl_clash_detect
}

# Engine capabilities --------------------------------------------------------
# The installed sing-box reports what it can do: podkop-engine (r11+) prints
# a "Features:" line in `sing-box version`, and `sing-box tools decode-link`
# builds an outbound for a link with the same code as `sing-box check`.
# SmartLink uses both: feature gates for options, decode-link as the exact
# per-link oracle (it catches everything Podkop would reject fatally,
# including future protocols no static parser knows about).

# The "Features:" line of `sing-box version`, comma-separated; empty for
# builds without it (cached per process).
sl_engine_features() {
    if [ -z "$_SL_ENGINE_FEATURES_LOADED" ]; then
        _SL_ENGINE_FEATURES_LOADED=1
        _SL_ENGINE_FEATURES="$(sing-box version 2>/dev/null | sed -n 's/^Features:[[:space:]]*//p')"
    fi
    printf '%s' "$_SL_ENGINE_FEATURES"
}

# True when the installed engine reports the given feature.
sl_engine_has_feature() {
    case ",$(sl_engine_features)," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

# Probe a link with `sing-box tools decode-link`. A successful decode means
# this exact link is usable by the installed engine; otherwise the engine's
# first error line is written to <err_file>.
# Args: <url> <err_file>
sl_engine_probe_link() {
    sing-box tools decode-link "$1" >/dev/null 2>"$2"
}

# Internal: curl with auth, returns body + http code on last line.
_sl_clash_curl() {
    local method="$1" path="$2" data="$3"
    local url="http://${_CLASH_BASE}${path}"

    set -- -s -w "\n%{http_code}" --max-time 10
    [ -n "$_CLASH_AUTH" ] && set -- "$@" --header "$_CLASH_AUTH"
    if [ "$method" = "GET" ]; then
        set -- "$@" "$url"
    else
        set -- "$@" -X "$method" -H "Content-Type: application/json" --data-raw "$data" "$url"
    fi
    curl "$@"
}

# Wait for Clash API to become reachable after a podkop reload.
sl_clash_wait_ready() {
    local waited=0
    sl_clash_detect
    while [ "$waited" -lt "$CLASH_API_READY_MAX_WAIT" ]; do
        local code
        code="$(_sl_clash_curl GET /proxies 2>/dev/null | tail -n1)"
        [ "$code" = "200" ] && return 0
        sleep "$CLASH_API_READY_POLL"
        waited=$((waited + CLASH_API_READY_POLL))
    done
    log "Clash API did not become ready within ${CLASH_API_READY_MAX_WAIT}s" "warn"
    return 1
}

# GET /proxies -> raw JSON to stdout. Re-detects once on failure.
sl_clash_get_proxies_raw() {
    sl_clash_detect
    local resp code
    resp="$(_sl_clash_curl GET /proxies 2>/dev/null)"
    code="$(printf '%s' "$resp" | tail -n1)"
    if [ "$code" != "200" ]; then
        sl_clash_redetect
        resp="$(_sl_clash_curl GET /proxies 2>/dev/null)"
        code="$(printf '%s' "$resp" | tail -n1)"
    fi
    [ "$code" != "200" ] && { log "get_proxies failed (http $code)" "error"; return 1; }
    printf '%s' "$resp" | sed '$d'
}

# Group tag for a section: <section>-out
sl_clash_group_tag() { printf '%s-out' "$1"; }

# Get ordered outbound tags belonging to the selector group.
sl_clash_get_outbound_tags() {
    sl_clash_get_proxies_raw 2>/dev/null | jq -r --arg g "$1" \
        '.proxies[$g].all // [] | if type == "array" then .[] else empty end' 2>/dev/null
}

# Get the currently selected proxy tag of a group (the `now` field).
sl_clash_get_group_now() {
    sl_clash_get_proxies_raw 2>/dev/null | jq -r --arg g "$1" '.proxies[$g].now // empty' 2>/dev/null
}

# Test latency of a single outbound through the tunnel.
# Args: <tag> [timeout_ms]
# Outputs: latency (ms) on stdout, or nothing on failure.
sl_clash_proxy_latency() {
    local tag="$1" timeout="${2:-$DEFAULT_PING_TIMEOUT}"
    sl_clash_detect

    local curl_max=$(( timeout / 1000 + 5 ))
    [ "$curl_max" -lt 10 ] && curl_max=10

    local resp code delay enc_tag test_url
    enc_tag="$(sl_uri_encode "$tag")"
    test_url="${SL_CFG_TEST_URL:-$DEFAULT_TEST_URL}"
    set -- -s -w "\n%{http_code}" --max-time "$curl_max" -G "http://${_CLASH_BASE}/proxies/${enc_tag}/delay" \
        --data-urlencode "url=${test_url}" --data-urlencode "timeout=${timeout}"
    [ -n "$_CLASH_AUTH" ] && set -- "$@" --header "$_CLASH_AUTH"
    resp="$(curl "$@" 2>/dev/null)"
    code="$(printf '%s' "$resp" | tail -n1)"
    [ "$code" != "200" ] && return 1

    delay="$(printf '%s' "$resp" | sed '$d' | jq -r '.delay // empty' 2>/dev/null)"
    [ -z "$delay" ] || [ "$delay" = "null" ] && return 1
    printf '%s' "$delay"
}

# Set the active proxy of a selector group (runtime, no reload).
# Args: <group_tag> <proxy_tag>
sl_clash_set_group() {
    local group_tag="$1" proxy_tag="$2"
    sl_clash_detect

    local body enc_group
    enc_group="$(sl_uri_encode "$group_tag")"
    body="$(jq -c -n --arg name "$proxy_tag" '{name:$name}')"
    local code
    code="$(_sl_clash_curl PUT "/proxies/${enc_group}" "$body" | tail -n1)"

    case "$code" in
        204|200) log "Switched group '$group_tag' -> '$proxy_tag'" "debug"; return 0 ;;
        404)     log "set_group: group '$group_tag' not found" "error"; return 1 ;;
        400)     log "set_group: proxy '$proxy_tag' not in group '$group_tag'" "error"; return 1 ;;
        *)       log "set_group failed (http $code)" "error"; return 1 ;;
    esac
}

# Write sorted alive+dead results from tmp_dir to out_file.
# Args: <out_file> <tmp_dir> <tags_file>
# Sets: SL_ALIVE_COUNT
_sl_clash_ping_collect() {
    local out_file="$1" tmp_dir="$2" tags_file="$3"
    SL_ALIVE_COUNT=0
    local alive_file="${out_file}.alive" dead_file="${out_file}.dead"
    : > "$alive_file"; : > "$dead_file"

    local tag lat key
    while IFS= read -r tag || [ -n "$tag" ]; do
        [ -z "$tag" ] && continue
        key="$(sl_text_key "$tag")"
        if [ -s "$tmp_dir/${key}.lat" ]; then
            read -r lat < "$tmp_dir/${key}.lat"
            printf '%s\t%s\n' "$lat" "$tag" >> "$alive_file"
            SL_ALIVE_COUNT=$((SL_ALIVE_COUNT + 1))
        else
            printf '\t%s\n' "$tag" >> "$dead_file"
        fi
    done < "$tags_file"

    sort -t "$TAB" -k1,1n "$alive_file" > "$out_file"
    cat "$dead_file" >> "$out_file"
    rm -f "$alive_file" "$dead_file"
}

# Ping a newline-delimited list of tags in parallel (batched to avoid NAT bottleneck).
# Writes sorted results to out_file.
# Args: <out_file> <timeout_ms> <tags_file>
# File format: "<latency_or_empty>\t<tag>" per line (alive sorted by latency, dead after).
# Sets: SL_ALIVE_COUNT
sl_clash_ping_tags_file() {
    local out_file="$1" timeout="$2" tags_file="$3"
    [ -s "$tags_file" ] || { SL_ALIVE_COUNT=0; : > "$out_file"; return 1; }

    sl_clash_detect
    local test_url="${SL_CFG_TEST_URL:-$DEFAULT_TEST_URL}"

    local curl_max=$(( timeout / 1000 + 5 ))
    [ "$curl_max" -lt 10 ] && curl_max=10

    local tmp_dir="${out_file}.pids"
    rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"

    local tag batch_count=0 key enc_tag
    while IFS= read -r tag || [ -n "$tag" ]; do
        [ -z "$tag" ] && continue
        key="$(sl_text_key "$tag")"
        enc_tag="$(sl_uri_encode "$tag")"
        (
            local resp code delay
            set -- -s -w "\n%{http_code}" --max-time "$curl_max" -G "http://${_CLASH_BASE}/proxies/${enc_tag}/delay" \
                --data-urlencode "url=${test_url}" --data-urlencode "timeout=${timeout}"
            [ -n "$_CLASH_AUTH" ] && set -- "$@" --header "$_CLASH_AUTH"
            resp="$(curl "$@" 2>/dev/null)"
            code="$(printf '%s' "$resp" | tail -n1)"
            if [ "$code" = "200" ]; then
                delay="$(printf '%s' "$resp" | sed '$d' | jq -r '.delay // empty' 2>/dev/null)"
                if [ -n "$delay" ] && [ "$delay" != "null" ]; then
                    printf '%s' "$delay" > "$tmp_dir/${key}.lat"
                fi
            fi
        ) &
        batch_count=$((batch_count + 1))
        if [ "$batch_count" -ge "$SL_PING_BATCH" ]; then
            wait
            batch_count=0
        fi
    done < "$tags_file"

    wait

    _sl_clash_ping_collect "$out_file" "$tmp_dir" "$tags_file"
    rm -rf "$tmp_dir"
    return 0
}

# Ping all outbounds in a group.
# Args: <group_tag> <out_file> [timeout_ms]
sl_clash_ping_group() {
    local group_tag="$1" out_file="$2" timeout="${3:-$DEFAULT_PING_TIMEOUT}"
    : > "$out_file"

    local tags_file="${out_file}.tags.$$"
    sl_clash_get_outbound_tags "$group_tag" > "$tags_file" 2>/dev/null
    [ -s "$tags_file" ] || { SL_ALIVE_COUNT=0; rm -f "$tags_file"; return 1; }

    sl_clash_ping_tags_file "$out_file" "$timeout" "$tags_file"
    local rc=$?
    rm -f "$tags_file"
    return $rc
}
