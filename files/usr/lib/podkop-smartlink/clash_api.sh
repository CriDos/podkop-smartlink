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

# Internal: curl with auth, returns body + http code on last line.
_sl_clash_curl() {
    local method="$1" path="$2" data="$3"
    local url="http://${_CLASH_BASE}${path}"

    if [ "$method" = "GET" ]; then
        if [ -n "$_CLASH_AUTH" ]; then
            curl -s -w "\n%{http_code}" --max-time 10 --header "$_CLASH_AUTH" "$url"
        else
            curl -s -w "\n%{http_code}" --max-time 10 "$url"
        fi
    else
        if [ -n "$_CLASH_AUTH" ]; then
            curl -s -w "\n%{http_code}" --max-time 10 -X "$method" \
                --header "$_CLASH_AUTH" \
                -H "Content-Type: application/json" --data-raw "$data" "$url"
        else
            curl -s -w "\n%{http_code}" --max-time 10 -X "$method" \
                -H "Content-Type: application/json" --data-raw "$data" "$url"
        fi
    fi
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

    local resp code delay
    if [ -n "$_CLASH_AUTH" ]; then
        resp="$(curl -s -w "\n%{http_code}" --max-time "$curl_max" -G "http://${_CLASH_BASE}/proxies/${tag}/delay" \
            --header "$_CLASH_AUTH" \
            --data-urlencode "url=${SL_CFG_TEST_URL:-$DEFAULT_TEST_URL}" \
            --data-urlencode "timeout=${timeout}" 2>/dev/null)"
    else
        resp="$(curl -s -w "\n%{http_code}" --max-time "$curl_max" -G "http://${_CLASH_BASE}/proxies/${tag}/delay" \
            --data-urlencode "url=${SL_CFG_TEST_URL:-$DEFAULT_TEST_URL}" \
            --data-urlencode "timeout=${timeout}" 2>/dev/null)"
    fi
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

    local body
    body="$(jq -c -n --arg name "$proxy_tag" '{name:$name}')"
    local code
    code="$(_sl_clash_curl PUT "/proxies/${group_tag}" "$body" | tail -n1)"

    case "$code" in
        204|200) log "Switched group '$group_tag' -> '$proxy_tag'" "info"; return 0 ;;
        404)     log "set_group: group '$group_tag' not found" "error"; return 1 ;;
        400)     log "set_group: proxy '$proxy_tag' not in group '$group_tag'" "error"; return 1 ;;
        *)       log "set_group failed (http $code)" "error"; return 1 ;;
    esac
}

# Write sorted alive+dead results from tmp_dir to out_file.
# Args: <out_file> <tmp_dir> <tag1> <tag2> ...
# Sets: SL_ALIVE_COUNT
_sl_clash_ping_collect() {
    local out_file="$1" tmp_dir="$2"
    shift 2
    SL_ALIVE_COUNT=0
    local alive_file="${out_file}.alive" dead_file="${out_file}.dead"
    : > "$alive_file"; : > "$dead_file"

    local tag lat
    for tag in "$@"; do
        if [ -s "$tmp_dir/${tag}.lat" ]; then
            read -r lat < "$tmp_dir/${tag}.lat"
            printf '%s\t%s\n' "$lat" "$tag" >> "$alive_file"
            SL_ALIVE_COUNT=$((SL_ALIVE_COUNT + 1))
        else
            printf '\t%s\n' "$tag" >> "$dead_file"
        fi
    done

    sort -t "$TAB" -k1,1n "$alive_file" > "$out_file"
    cat "$dead_file" >> "$out_file"
    rm -f "$alive_file" "$dead_file"
}

# Ping a list of tags in parallel (batched to avoid NAT bottleneck).
# Writes sorted results to out_file.
# Args: <out_file> <timeout_ms> <tag1> <tag2> ...
# File format: "<latency_or_empty>\t<tag>" per line (alive sorted by latency, dead after).
# Sets: SL_ALIVE_COUNT
SL_PING_BATCH=10

sl_clash_ping_tags() {
    local out_file="$1" timeout="$2"
    shift 2
    [ -z "$1" ] && { SL_ALIVE_COUNT=0; : > "$out_file"; return 1; }

    sl_clash_detect
    local test_url="${SL_CFG_TEST_URL:-$DEFAULT_TEST_URL}"
    local auth=""
    [ -n "$_CLASH_AUTH" ] && auth="$_CLASH_AUTH"

    local curl_max=$(( timeout / 1000 + 5 ))
    [ "$curl_max" -lt 10 ] && curl_max=10

    local tmp_dir="${out_file}.pids"
    rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"

    local tag batch_count=0
    for tag in "$@"; do
        (
            local resp code delay
            resp="$(curl -s -w "\n%{http_code}" --max-time "$curl_max" -G "http://${_CLASH_BASE}/proxies/${tag}/delay" \
                ${auth:+--header "$auth"} \
                --data-urlencode "url=${test_url}" \
                --data-urlencode "timeout=${timeout}" 2>/dev/null)"
            code="$(printf '%s' "$resp" | tail -n1)"
            if [ "$code" = "200" ]; then
                delay="$(printf '%s' "$resp" | sed '$d' | jq -r '.delay // empty' 2>/dev/null)"
                if [ -n "$delay" ] && [ "$delay" != "null" ]; then
                    printf '%s' "$delay" > "$tmp_dir/${tag}.lat"
                fi
            fi
        ) &
        batch_count=$((batch_count + 1))
        if [ "$batch_count" -ge "$SL_PING_BATCH" ]; then
            wait
            batch_count=0
        fi
    done

    wait

    _sl_clash_ping_collect "$out_file" "$tmp_dir" "$@"
    rm -rf "$tmp_dir"
    return 0
}

# Ping all outbounds in a group.
# Args: <group_tag> <out_file> [timeout_ms] [sequential:0|1]
# Sequential mode (1) pings one-by-one for accurate stability stats.
sl_clash_ping_group() {
    local group_tag="$1" out_file="$2" timeout="${3:-$DEFAULT_PING_TIMEOUT}" sequential="${4:-0}"
    : > "$out_file"

    local tags
    tags="$(sl_clash_get_outbound_tags "$group_tag")"
    [ -z "$tags" ] && { SL_ALIVE_COUNT=0; return 1; }

    if [ "$sequential" = "1" ]; then
        local tmp_dir="${out_file}.seq"
        rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"
        local tag lat
        for tag in $tags; do
            lat="$(sl_clash_proxy_latency "$tag" "$timeout")"
            if [ -n "$lat" ]; then
                printf '%s' "$lat" > "$tmp_dir/${tag}.lat"
            fi
        done
        # shellcheck disable=SC2086
        _sl_clash_ping_collect "$out_file" "$tmp_dir" $tags
        rm -rf "$tmp_dir"
        return 0
    fi

    # Parallel mode
    # shellcheck disable=SC2086
    sl_clash_ping_tags "$out_file" "$timeout" $tags
}
