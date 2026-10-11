# Subscription fetch & parse for podkop-smartlink
# Supports base64 subscriptions and plain-text URL lists.
# Supported schemes: vless ss trojan hy2 hysteria2 socks socks4 socks5

# Compute 8-char md5 hash of a URL (for cache file naming).
sl_sub_hash() {
    printf '%s' "$1" | md5sum | cut -c1-8
}

# Check if a URL is a supported proxy link (case-insensitive scheme).
# The common path (already lowercased scheme) needs no subprocess.
sl_sub_is_supported() {
    local scheme
    case "$1" in
        *://*) ;;
        *) return 1 ;;
    esac
    scheme="${1%%://*}"
    case "$scheme" in
        vless|ss|trojan|hy2|hysteria2|socks|socks4|socks5) return 0 ;;
        *[A-Z]*) ;;
        *) return 1 ;;
    esac
    case "$(printf '%s' "$scheme" | tr 'A-Z' 'a-z')" in
        vless|ss|trojan|hy2|hysteria2|socks|socks4|socks5) return 0 ;;
    esac
    return 1
}

sl_sub_normalize_url() {
    printf '%s' "$1" | tr '\t\r\n' '   ' | sed 's/ /%20/g'
}

sl_sub_normalize_scheme() {
    local url="$1" scheme rest
    case "$url" in
        *://*)
            scheme="${url%%://*}"
            rest="${url#*://}"
            printf '%s://%s' "$(printf '%s' "$scheme" | tr 'A-Z' 'a-z')" "$rest"
            ;;
        *) printf '%s' "$url" ;;
    esac
}

# Make VLESS UDP packet encoding explicit for Podkop-generated outbounds.
# Keep an explicitly supplied value untouched; only add xudp when the
# subscription omitted packetEncoding entirely. The parameter belongs before
# the URL fragment so it is parsed as a query option by Podkop.
sl_sub_ensure_packet_encoding() {
    local url="$1" base fragment query prefix token key value new_query has_param
    case "$url" in
        vless://*) ;;
        *) printf '%s' "$url"; return 0 ;;
    esac

    case "$url" in
        *\#*)
            base="${url%%#*}"
            fragment="#${url#*#}"
            ;;
        *)
            base="$url"
            fragment=""
            ;;
    esac

    case "$base" in
        *\?*)
            prefix="${base%%\?*}"
            query="${base#*\?}"
            ;;
        *)
            printf '%s?packetEncoding=xudp%s' "$base" "$fragment"
            return 0
    esac

    new_query=""
    has_param=0
    # Read tokens line-by-line so shell pathname expansion cannot rewrite a
    # query value containing wildcard characters.
    while IFS= read -r token || [ -n "$token" ]; do
        key="${token%%=*}"
        value=""
        case "$token" in
            *=*) value="${token#*=}" ;;
        esac
        if [ "$key" = "packetEncoding" ]; then
            has_param=1
            [ -n "$value" ] || token="packetEncoding=xudp"
        fi
        if [ -n "$new_query" ]; then
            new_query="${new_query}&${token}"
        else
            new_query="$token"
        fi
    done <<EOF
$(printf '%s' "$query" | tr '&' '\n')
EOF

    if [ "$has_param" -eq 0 ]; then
        [ -n "$new_query" ] && new_query="${new_query}&"
        new_query="${new_query}packetEncoding=xudp"
    fi

    printf '%s?%s%s' "$prefix" "$new_query" "$fragment"
}

# Make VLESS/Trojan transport and security explicit for Podkop-generated
# outbounds. Podkop logs "Unknown transport/security ''" and (for trojan)
# never configures TLS when the parameter is missing; the protocol defaults
# are type=tcp, security=none for VLESS and type=tcp, security=tls for
# Trojan. Only missing or empty values are filled in; explicit values
# (ws, grpc, xhttp, raw, reality, ...) are kept untouched. The parameters
# belong before the URL fragment so Podkop parses them as query options.
sl_sub_ensure_transport_security() {
    local url="$1" scheme default_type default_security base fragment query prefix token key value key_lc new_query has_type has_security
    case "$url" in
        *://*) scheme="${url%%://*}" ;;
        *) printf '%s' "$url"; return 0 ;;
    esac
    case "$scheme" in *[A-Z]*) scheme="$(printf '%s' "$scheme" | tr 'A-Z' 'a-z')" ;; esac
    case "$scheme" in
        vless) default_type="tcp"; default_security="none" ;;
        trojan) default_type="tcp"; default_security="tls" ;;
        *) printf '%s' "$url"; return 0 ;;
    esac

    case "$url" in
        *\#*)
            base="${url%%#*}"
            fragment="#${url#*#}"
            ;;
        *)
            base="$url"
            fragment=""
            ;;
    esac

    case "$base" in
        *\?*)
            prefix="${base%%\?*}"
            query="${base#*\?}"
            ;;
        *)
            printf '%s?type=%s&security=%s%s' "$base" "$default_type" "$default_security" "$fragment"
            return 0
    esac

    new_query=""
    has_type=0
    has_security=0
    # Read tokens line-by-line so shell pathname expansion cannot rewrite a
    # query value containing wildcard characters.
    while IFS= read -r token || [ -n "$token" ]; do
        key="${token%%=*}"
        value=""
        case "$token" in
            *=*) value="${token#*=}" ;;
        esac
        key_lc="$key"
        case "$key" in *[A-Z]*) key_lc="$(printf '%s' "$key" | tr 'A-Z' 'a-z')" ;; esac
        if [ "$key_lc" = "type" ]; then
            has_type=1
            [ -n "$value" ] || token="type=$default_type"
        elif [ "$key_lc" = "security" ]; then
            has_security=1
            [ -n "$value" ] || token="security=$default_security"
        fi
        if [ -n "$new_query" ]; then
            new_query="${new_query}&${token}"
        else
            new_query="$token"
        fi
    done <<EOF
$(printf '%s' "$query" | tr '&' '\n')
EOF

    if [ "$has_type" -eq 0 ]; then
        [ -n "$new_query" ] && new_query="${new_query}&"
        new_query="${new_query}type=$default_type"
    fi
    if [ "$has_security" -eq 0 ]; then
        [ -n "$new_query" ] && new_query="${new_query}&"
        new_query="${new_query}security=$default_security"
    fi

    printf '%s?%s%s' "$prefix" "$new_query" "$fragment"
}

# Normalize cached subscription entries after the parser behavior changes.
# Cache files contain URL/title/host fields and are otherwise reused without
# passing through sl_sub_process_link again.
sl_sub_cache_normalize() {
    local cache_file="$1" tmp url title host
    [ -s "$cache_file" ] || return 0
    # Rewriting is only needed when a link is missing packetEncoding, type or
    # security; skip the per-line rewrite entirely when there are none.
    if ! awk -F "$TAB" '
        $1 ~ /^vless:\/\// && $1 !~ /packetEncoding=[^&]/ { found = 1; exit }
        $1 ~ /^(vless|trojan):\/\// && ($1 !~ /[?&]type=[^&#]/ || $1 !~ /[?&]security=[^&#]/) { found = 1; exit }
        END { exit !found }
    ' "$cache_file" 2>/dev/null; then
        return 0
    fi
    tmp="${cache_file}.normalize.$$"
    : > "$tmp" || return 1
    while IFS="$TAB" read -r url title host; do
        [ -n "$url" ] || continue
        url="$(sl_sub_ensure_packet_encoding "$url")"
        url="$(sl_sub_ensure_transport_security "$url")"
        printf '%s\t%s\t%s\n' "$url" "$title" "$host" >> "$tmp"
    done < "$cache_file"
    mv "$tmp" "$cache_file" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

# Extract the fragment (title) from a proxy URL, after the first '#'.
# Decoded, sanitized (tabs/newlines -> spaces).
sl_sub_extract_title() {
    local title="$1"
    case "$title" in
        *\#*) title="${title#*\#}" ;;
        *) title="" ;;
    esac
    [ -z "$title" ] && title="$2"
    printf '%s' "$(sl_url_decode "$title")" | tr '\t\r\n' '   '
}

# Strip userinfo, path, query, fragment and port from a URL authority.
_sl_sub_host_from_authority() {
    local core="$1"
    core="${core%%[/?#]*}"
    case "$core" in
        \[*\]*) core="${core#\[}"; core="${core%%\]*}" ;;
        *) core="${core%%:*}" ;;
    esac
    printf '%s' "$core"
}

# Extract the host from a proxy URL.
sl_sub_extract_host() {
    local url="$1" core
    case "$url" in
        vless://*|trojan://*|hy2://*|hysteria2://*|socks://*|socks4://*|socks5://*)
            core="${url#*://}"
            case "$core" in *@*) core="${core#*@}" ;; esac
            _sl_sub_host_from_authority "$core"
            ;;
        ss://*)
            core="${url#ss://}"
            case "$core" in
                *@*)
                    _sl_sub_host_from_authority "${core#*@}"
                    ;;
                *)
                    local enc dec
                    enc="$(printf '%s' "$core" | sed 's/[/?#].*$//')"
                    # Add base64 padding (busybox base64 -d requires it)
                    case $((${#enc} % 4)) in
                        1) enc="${enc}===" ;;
                        2) enc="${enc}==" ;;
                        3) enc="${enc}=" ;;
                    esac
                    dec="$(printf '%s' "$enc" | base64 -d 2>/dev/null || true)"
                    case "$dec" in
                        *@*) _sl_sub_host_from_authority "${dec#*@}" ;;
                    esac
                    ;;
            esac
            ;;
    esac
}

# Check if a host is an IP address (IPv4 or IPv6 bracketed).
sl_sub_is_ip() {
    local host="$1"
    case "$host" in
        [0-9]*.[0-9]*.[0-9]*.[0-9]*)
            # Validate: 4 octets, 0-255 each (without set -- to preserve caller $@)
            local valid
            valid="$(printf '%s' "$host" | awk -F. '{
                if (NF != 4) { print 0; exit }
                for (i = 1; i <= 4; i++) {
                    if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) { print 0; exit }
                }
                print 1
            }')"
            [ "$valid" = "1" ] && return 0
            return 1 ;;
        \[*\]|*:*) return 0 ;;
    esac
    return 1
}

# Check if a host resolves via DNS (skips IP addresses).
# Busybox nslookup has no timeout option; the caller bounds it (see
# sl_sub_resolve_batch) when many hosts are probed at once.
sl_sub_host_resolvable() {
    local host="$1"
    [ -z "$host" ] && return 1
    sl_sub_is_ip "$host" && return 0
    nslookup "$host" 127.0.0.1 >/dev/null 2>&1 || ping -c1 -W2 "$host" >/dev/null 2>&1
}

# Wait for a probe wave; a watchdog kills stragglers after <timeout> seconds
# so a hung resolver or engine probe cannot stall the wave (busybox sleep has
# no sub-second resolution; nslookup/decode-link have no timeout option).
# Args: <pids> <timeout_sec>
_sl_sub_wait_wave() {
    local pids="$1" timeout="$2" watchdog pid
    [ -n "$pids" ] || return 0
    ( sleep "$timeout"
      kill $pids 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    watchdog=$!
    for pid in $pids; do
        wait "$pid" 2>/dev/null
    done
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    return 0
}

# Resolve unique hosts in parallel batches, appending "host<TAB>ok" rows to
# the resolve cache. Hosts already present in the cache are skipped.
# Args: <hosts_file> <cache_file>
sl_sub_resolve_batch() {
    local hosts_file="$1" cache_file="$2"
    [ -s "$hosts_file" ] || return 0

    local pending_file="${cache_file}.pending.$$"
    if [ -s "$cache_file" ]; then
        awk -F "$TAB" 'NR==FNR { c[$1]=1; next } !($1 in c)' \
            "$cache_file" "$hosts_file" > "$pending_file" 2>/dev/null
    else
        cp "$hosts_file" "$pending_file" 2>/dev/null || : > "$pending_file"
    fi
    [ -s "$pending_file" ] || { rm -f "$pending_file"; return 0; }

    local tmp_dir="${cache_file}.probe.$$"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    local host key count=0 pids=""
    while IFS= read -r host || [ -n "$host" ]; do
        [ -z "$host" ] && continue
        key="$(sl_text_key "$host")"
        (
            sl_sub_host_resolvable "$host" && printf '1' > "$tmp_dir/$key"
        ) &
        pids="$pids $!"
        count=$((count + 1))
        if [ "$count" -ge "$SL_RESOLVE_BATCH" ]; then
            _sl_sub_wait_wave "$pids" "$SL_RESOLVE_TIMEOUT"
            pids=""
            count=0
        fi
    done < "$pending_file"
    [ -n "$pids" ] && _sl_sub_wait_wave "$pids" "$SL_RESOLVE_TIMEOUT"

    local ok
    while IFS= read -r host || [ -n "$host" ]; do
        [ -z "$host" ] && continue
        key="$(sl_text_key "$host")"
        if [ -s "$tmp_dir/$key" ]; then ok=1; else ok=0; fi
        printf '%s\t%s\n' "$host" "$ok" >> "$cache_file"
    done < "$pending_file"

    rm -rf "$tmp_dir" "$pending_file"
    return 0
}

sl_sub_host_resolvable_cached() {
    local host="$1" cache_file="$2" hit ok
    [ -n "$cache_file" ] || { sl_sub_host_resolvable "$host"; return $?; }
    hit="$(awk -F "$TAB" -v h="$host" '$1==h{print $2; exit}' "$cache_file" 2>/dev/null)"
    case "$hit" in
        1) return 0 ;;
        0) return 1 ;;
    esac
    if sl_sub_host_resolvable "$host"; then
        ok=1
    else
        ok=0
    fi
    printf '%s\t%s\n' "$host" "$ok" >> "$cache_file"
    [ "$ok" = "1" ]
}

# Extract the transport type from a proxy URL (the `type=` query param).
# Defaults to "tcp" if not specified. Query parsing is pure shell so the
# per-link hot path does not fork.
sl_sub_extract_transport() {
    local url="$1" scheme rest tok key val
    scheme="${url%%://*}"
    case "$scheme" in
        ss|hy2|hysteria2|socks|socks4|socks5) printf 'tcp'; return ;;
        *[A-Z]*) scheme="$(printf '%s' "$scheme" | tr 'A-Z' 'a-z')" ;;
    esac
    case "$scheme" in
        ss|hy2|hysteria2|socks|socks4|socks5) printf 'tcp'; return ;;
    esac

    case "$url" in
        *\?*) rest="${url#*\?}" ;;
        *) printf 'tcp'; return ;;
    esac
    rest="${rest%%#*}"
    val=""
    while [ -n "$rest" ]; do
        tok="${rest%%&*}"
        case "$rest" in
            *\&*) rest="${rest#*\&}" ;;
            *) rest="" ;;
        esac
        key="${tok%%=*}"
        case "$key" in *[A-Z]*) key="$(printf '%s' "$key" | tr 'A-Z' 'a-z')" ;; esac
        if [ "$key" = "type" ]; then
            case "$tok" in
                *=*) val="${tok#*=}" ;;
                *) val="" ;;
            esac
            case "$val" in *[A-Z]*) val="$(printf '%s' "$val" | tr 'A-Z' 'a-z')" ;; esac
            break
        fi
    done
    [ -z "$val" ] && val="tcp"
    printf '%s' "$val"
}

# Check if a transport type is supported.
sl_sub_transport_supported() {
    local t
    for t in $SUPPORTED_TRANSPORTS; do
        [ "$t" = "$1" ] && return 0
    done
    return 1
}

# Check the VLESS encryption parameter. Xray 25.x added VLESS Encryption
# (encryption=mlkem768x25519plus...); sing-box (including podkop-engine)
# does not implement it and podkop fatally aborts on such links, so they
# are dropped at import. Absent or "none" is fine.
sl_sub_vless_encryption_ok() {
    local rest tok key val
    case "$1" in
        vless://*) ;;
        *) return 0 ;;
    esac
    case "$1" in
        *\?*) rest="${1#*\?}" ;;
        *) return 0 ;;
    esac
    rest="${rest%%#*}"
    while [ -n "$rest" ]; do
        tok="${rest%%&*}"
        case "$rest" in
            *\&*) rest="${rest#*\&}" ;;
            *) rest="" ;;
        esac
        key="${tok%%=*}"
        case "$key" in *[A-Z]*) key="$(printf '%s' "$key" | tr 'A-Z' 'a-z')" ;; esac
        if [ "$key" = "encryption" ]; then
            case "$tok" in
                *=*) val="${tok#*=}" ;;
                *) val="" ;;
            esac
            case "$val" in *[A-Z]*) val="$(printf '%s' "$val" | tr 'A-Z' 'a-z')" ;; esac
            [ -z "$val" ] && return 0
            [ "$val" = "none" ] && return 0
            return 1
        fi
    done
    return 0
}

# Prepare a proxy link for import: normalize, check scheme/transport.
# No DNS here — hosts are resolved separately (in parallel batches) so a slow
# resolver cannot serialize the import.
# Args: <raw_url> <idx>
# Echoes "<url>\t<title>\t<host>". Returns 1 if the link is unsupported.
sl_sub_prepare_link() {
    local url="$1" idx="$2"
    url="$(sl_sub_normalize_scheme "$(sl_sub_normalize_url "$url")")"
    url="$(sl_sub_ensure_packet_encoding "$url")"
    url="$(sl_sub_ensure_transport_security "$url")"
    sl_sub_is_supported "$url" || return 1
    local title host
    title="$(sl_sub_extract_title "$url" "Config $idx")"
    host="$(sl_sub_extract_host "$url")"
    [ -n "$host" ] || return 1
    printf '%s\t%s\t%s' "$url" "$title" "$host"
    return 0
}

# Process a single proxy link: prepare + DNS check + append to out_file.
# Args: <url> <out_file> <idx> <source_idx> [resolve_cache_file]
# Returns 0 if appended, 1 if skipped.
sl_sub_process_link() {
    local url="$1" out_file="$2" idx="$3" src_idx="$4" resolve_cache="$5"
    local prepared
    prepared="$(sl_sub_prepare_link "$url" "$idx")" || return 1

    local p_url p_title p_host rest
    p_url="${prepared%%"$TAB"*}"
    rest="${prepared#*"$TAB"}"
    p_title="${rest%%"$TAB"*}"
    p_host="${rest#*"$TAB"}"

    if ! sl_sub_host_resolvable_cached "$p_host" "$resolve_cache"; then
        log "Skipping unresolvable host '$p_host': $p_title" "debug"
        return 1
    fi
    printf '%s\t%s\t%s\t%s\n' "$p_url" "$p_title" "$p_host" "$src_idx" >> "$out_file"
}

# Single-pass awk parser for subscription imports. Mirrors sl_sub_prepare_link
# exactly (normalize, VLESS packetEncoding, title decode, host extraction)
# with one process per subscription instead of ~10 forks per link.
# Unsupported links are dropped silently; engine compatibility is enforced
# later by the publish gate.
_SL_SUB_PREPARE_PROGRAM='
BEGIN { idx = start + 0; OFS = "\t" }

function hx(c) {
    if (c >= "0" && c <= "9") return c + 0
    c = tolower(c)
    if (c >= "a" && c <= "f") return index("abcdef", c) + 9
    return -1
}

function pct_decode(s,   out, i, n, c, h1, h2, v) {
    out = ""
    n = length(s)
    i = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "+") { out = out " "; i++; continue }
        if (c == "%") {
            h1 = (i + 1 <= n ? hx(substr(s, i + 1, 1)) : -1)
            if (h1 >= 0) {
                h2 = (i + 2 <= n ? hx(substr(s, i + 2, 1)) : -1)
                if (h2 >= 0) { v = h1 * 16 + h2; i += 3 }
                else { v = h1; i += 2 }
                out = out sprintf("%c", v)
                continue
            }
            # busybox printf %b keeps a bad escape literal (\% becomes \x)
            out = out "\\x"
            i++
            continue
        }
        out = out c
        i++
    }
    return out
}

function ensure_pe(u,   hpos, base, frag, qpos, prefix, query, n, parts, i, tk, k, v, has, out) {
    if (substr(u, 1, 8) != "vless://") return u
    hpos = index(u, "#")
    if (hpos > 0) { frag = substr(u, hpos); base = substr(u, 1, hpos - 1) }
    else { frag = ""; base = u }
    qpos = index(base, "?")
    if (qpos == 0) return base "?packetEncoding=xudp" frag
    prefix = substr(base, 1, qpos - 1)
    query = substr(base, qpos + 1)
    n = split(query, parts, "&")
    has = 0
    out = ""
    for (i = 1; i <= n; i++) {
        tk = parts[i]
        k = tk
        sub(/=.*/, "", k)
        v = ""
        if (index(tk, "=") > 0) v = substr(tk, index(tk, "=") + 1)
        if (k == "packetEncoding") {
            has = 1
            if (v == "") tk = "packetEncoding=xudp"
        }
        out = (out == "" ? tk : out "&" tk)
    }
    if (!has) {
        if (out != "") out = out "&"
        out = out "packetEncoding=xudp"
    }
    return prefix "?" out frag
}

function ensure_params(u, scheme,   hpos, base, frag, qpos, prefix, query, n, parts, i, tk, k, v, lk, has_type, has_security, out, dt, ds) {
    if (scheme != "vless" && scheme != "trojan") return u
    if (scheme == "trojan") { dt = "tcp"; ds = "tls" } else { dt = "tcp"; ds = "none" }
    hpos = index(u, "#")
    if (hpos > 0) { frag = substr(u, hpos); base = substr(u, 1, hpos - 1) }
    else { frag = ""; base = u }
    qpos = index(base, "?")
    if (qpos == 0) return base "?type=" dt "&security=" ds frag
    prefix = substr(base, 1, qpos - 1)
    query = substr(base, qpos + 1)
    n = split(query, parts, "&")
    has_type = 0
    has_security = 0
    out = ""
    for (i = 1; i <= n; i++) {
        tk = parts[i]
        k = tk
        sub(/=.*/, "", k)
        v = ""
        if (index(tk, "=") > 0) v = substr(tk, index(tk, "=") + 1)
        lk = tolower(k)
        if (lk == "type") {
            has_type = 1
            if (v == "") tk = "type=" dt
        } else if (lk == "security") {
            has_security = 1
            if (v == "") tk = "security=" ds
        }
        out = (out == "" ? tk : out "&" tk)
    }
    if (!has_type) out = (out == "" ? "" : out "&") "type=" dt
    if (!has_security) out = (out == "" ? "" : out "&") "security=" ds
    return prefix "?" out frag
}

function authority_host(core,   p, i, ch) {
    p = 0
    for (i = 1; i <= length(core); i++) {
        ch = substr(core, i, 1)
        if (ch == "/" || ch == "?" || ch == "#") { p = i; break }
    }
    if (p > 0) core = substr(core, 1, p - 1)
    if (substr(core, 1, 1) == "[") {
        p = index(core, "]")
        if (p > 0) return substr(core, 2, p - 2)
    }
    p = index(core, ":")
    if (p > 0) core = substr(core, 1, p - 1)
    return core
}

function b64decode(s,   chars, i, n, c, p, acc, bits, out) {
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    out = ""
    acc = 0
    bits = 0
    n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "=") break
        p = index(chars, c)
        if (p == 0) return ""
        acc = acc * 64 + (p - 1)
        bits += 6
        if (bits >= 8) {
            bits -= 8
            out = out sprintf("%c", int(acc / (2 ^ bits)) % 256)
            acc = acc - int(acc / (2 ^ bits)) * (2 ^ bits)
        }
    }
    return out
}

function extract_host(u, scheme,   p, core, dec, pad) {
    if (scheme == "ss") {
        core = substr(u, 6)
        p = index(core, "@")
        if (p > 0) return authority_host(substr(core, p + 1))
        dec = core
        sub(/[\/?#].*/, "", dec)
        pad = length(dec) % 4
        if (pad == 1) dec = dec "==="
        else if (pad == 2) dec = dec "=="
        else if (pad == 3) dec = dec "="
        dec = b64decode(dec)
        p = index(dec, "@")
        if (p > 0) return authority_host(substr(dec, p + 1))
        return ""
    }
    p = index(u, "://")
    core = substr(u, p + 3)
    p = index(core, "@")
    if (p > 0) core = substr(core, p + 1)
    return authority_host(core)
}

{
    line = $0
    sub(/^[[:space:]]+/, "", line)
    sub(/[[:space:]]+$/, "", line)
    if (line == "") next

    p = index(line, "://")
    if (p == 0) next
    scheme = tolower(substr(line, 1, p - 1))
    line = scheme substr(line, p)
    if (scheme != "vless" && scheme != "ss" && scheme != "trojan" && scheme != "hy2" && scheme != "hysteria2" && scheme != "socks" && scheme != "socks4" && scheme != "socks5") next

    gsub(/[\t\r]/, " ", line)
    gsub(/ /, "%20", line)

    if (scheme == "vless") line = ensure_pe(line)
    if (scheme == "vless" || scheme == "trojan") line = ensure_params(line, scheme)

    p = index(line, "#")
    if (p > 0) frag = substr(line, p + 1)
    else frag = ""
    if (frag == "") title = "Config " idx
    else title = pct_decode(frag)
    gsub(/[\t\r\n]/, " ", title)

    host = extract_host(line, scheme)
    if (host == "") next

    print line, title, host
    idx++
}
'

# Parse a decoded subscription file into prepared "<url>\t<title>\t<host>"
# rows (see _SL_SUB_PREPARE_PROGRAM). Args: <in_file> <out_file> <start_idx>
_sl_sub_prepare_stream() {
    local in_file="$1" out_file="$2" start_idx="$3"
    : > "$out_file"
    awk -v start="$start_idx" "$_SL_SUB_PREPARE_PROGRAM" "$in_file" > "$out_file" 2>/dev/null
}

# Apply a user exclusion filter to prepared rows (single awk pass).
# Rows are already normalized by the parser/cache normalizer, so field 1 is
# written through unchanged. Matching rows are appended to the excluded file
# with the matched filter item appended; others are appended to the active
# file. Both outputs are appended to (several sources share the same files).
# Args: <in_file> <active_file> <excluded_file> <filter>
sl_sub_apply_user_filter_file() {
    local in_file="$1" active_file="$2" excluded_file="$3" filter="$4"
    SL_SUB_FILTER="$filter" awk -F "$TAB" -v active="$active_file" -v excluded="$excluded_file" '
        BEGIN {
            n = split(ENVIRON["SL_SUB_FILTER"], items, ";")
            m = 0
            for (i = 1; i <= n; i++) {
                it = items[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", it)
                if (it == "") continue
                m++
                orig[m] = it
                low[m] = tolower(it)
            }
        }
        {
            hay = tolower($2 " " $3 " " $1)
            reason = ""
            for (i = 1; i <= m; i++) {
                if (index(hay, low[i]) > 0) { reason = orig[i]; break }
            }
            if (reason != "") print $0 "\t" reason >> excluded
            else print $0 >> active
        }
    ' "$in_file"
}

# Drop an `fp` query parameter whose value sing-box does not know (a known
# value is lowercased instead). Podkop re-reads `fp` from the URL when it
# builds TLS settings, so an unknown value (e.g. Xray's "unsafe") makes the
# whole generated config invalid; dropping it means "no uTLS emulation",
# which is also what decode-link does with unknown fingerprints.
# Args: <url>; echoes the repaired URL.
sl_sub_repair_utls_fp() {
    local url="$1" base fragment prefix query tok key key_lc val val_lc new_query f known
    case "$url" in
        *fp=*) ;;
        *) printf '%s' "$url"; return 0 ;;
    esac

    case "$url" in
        *\#*) base="${url%%#*}"; fragment="#${url#*#}" ;;
        *) base="$url"; fragment="" ;;
    esac
    case "$base" in
        *\?*) prefix="${base%%\?*}"; query="${base#*\?}" ;;
        *) printf '%s' "$url"; return 0 ;;
    esac

    new_query=""
    while IFS= read -r tok || [ -n "$tok" ]; do
        [ -n "$tok" ] || continue
        key="${tok%%=*}"
        key_lc="$key"
        case "$key" in *[A-Z]*) key_lc="$(printf '%s' "$key" | tr 'A-Z' 'a-z')" ;; esac
        if [ "$key_lc" = "fp" ]; then
            val=""
            case "$tok" in *=*) val="${tok#*=}" ;; esac
            val_lc="$val"
            case "$val" in *[A-Z]*) val_lc="$(printf '%s' "$val" | tr 'A-Z' 'a-z')" ;; esac
            if [ -n "$val_lc" ]; then
                known=0
                for f in $SL_UTLS_FINGERPRINTS; do
                    [ "$f" = "$val_lc" ] && { known=1; break; }
                done
                [ "$known" -eq 0 ] && continue
                tok="fp=$val_lc"
            fi
        fi
        new_query="${new_query:+$new_query&}$tok"
    done <<EOF
$(printf '%s' "$query" | tr '&' '\n')
EOF

    if [ -n "$new_query" ]; then
        printf '%s?%s%s' "$prefix" "$new_query" "$fragment"
    else
        printf '%s%s' "$prefix" "$fragment"
    fi
}

# Publish gate: keep only links the installed engine can actually use.
# With tools.decode-link every row is probed by the engine itself (same code
# as `sing-box check`), which catches unsupported transports, encryption
# schemes and future protocols no static check knows about. Without the
# feature, rows fall back to the static transport/encryption checks so a
# cache written by an older engine cannot crash Podkop either.
# Args: <in_file> <out_file> <skipped_file>
# Skipped rows: "<url>\t<title>\t<reason>".
sl_sub_engine_gate() {
    local in_file="$1" out_file="$2" skipped_file="$3"
    : > "$out_file"
    : > "$skipped_file"
    [ -s "$in_file" ] || return 0

    local tmp_dir="${out_file}.probe.$$"
    rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"

    # Repair rows first (one pass) so probing, keys and output all agree.
    local url title host src repaired
    local work_file="$tmp_dir/input"
    : > "$work_file"
    while IFS="$TAB" read -r url title host src || [ -n "$url" ]; do
        [ -n "$url" ] || continue
        repaired="$(sl_sub_repair_utls_fp "$url")"
        if [ "$repaired" != "$url" ]; then
            log "Repaired '$title': dropped unsupported uTLS fingerprint" "debug"
            url="$repaired"
        fi
        printf '%s\t%s\t%s\t%s\n' "$url" "$title" "$host" "$src" >> "$work_file"
    done < "$in_file"

    if ! sl_engine_has_feature "tools.decode-link"; then
        while IFS="$TAB" read -r url title host src || [ -n "$url" ]; do
            [ -n "$url" ] || continue
            if ! sl_sub_transport_supported "$(sl_sub_extract_transport "$url")"; then
                printf '%s\t%s\t%s\n' "$url" "$title" "unsupported transport" >> "$skipped_file"
                continue
            fi
            if ! sl_sub_vless_encryption_ok "$url"; then
                printf '%s\t%s\t%s\n' "$url" "$title" "unsupported encryption" >> "$skipped_file"
                continue
            fi
            printf '%s\t%s\t%s\t%s\n' "$url" "$title" "$host" "$src" >> "$out_file"
        done < "$work_file"
        rm -rf "$tmp_dir"
        return 0
    fi

    local count=0 pids="" key
    while IFS="$TAB" read -r url title host src || [ -n "$url" ]; do
        [ -n "$url" ] || continue
        key="$(sl_text_key "$url")"
        (
            if sl_engine_probe_link "$url" "$tmp_dir/${key}.err"; then
                printf '%s\t%s\t%s\t%s\n' "$url" "$title" "$host" "$src" > "$tmp_dir/${key}.row"
            fi
        ) &
        pids="$pids $!"
        count=$((count + 1))
        if [ "$count" -ge "$SL_PROBE_BATCH" ]; then
            _sl_sub_wait_wave "$pids" "$SL_PROBE_TIMEOUT"
            pids=""; count=0
        fi
    done < "$work_file"
    [ -n "$pids" ] && _sl_sub_wait_wave "$pids" "$SL_PROBE_TIMEOUT"

    local reason
    while IFS="$TAB" read -r url title host src || [ -n "$url" ]; do
        [ -n "$url" ] || continue
        key="$(sl_text_key "$url")"
        if [ -s "$tmp_dir/${key}.row" ]; then
            cat "$tmp_dir/${key}.row" >> "$out_file"
        else
            reason="$(head -n 1 "$tmp_dir/${key}.err" 2>/dev/null)"
            [ -n "$reason" ] || reason="engine rejected the link"
            printf '%s\t%s\t%s\n' "$url" "$title" "$reason" >> "$skipped_file"
        fi
    done < "$work_file"
    rm -rf "$tmp_dir"
    return 0
}

# Fetch a single subscription URL and append parsed lines to out_file.
# Line format: "<url>\t<title>\t<host>\t<source_idx>"
# Args: <sub_url> <out_file> <start_idx> <source_idx> [resolve_cache_file]
# Returns 0 if at least one line appended.
sl_sub_fetch_one() {
    local sub_url="$1" out_file="$2" idx="$3" src_idx="$4" resolve_cache="$5"
    local raw_file dec_file attempt
    raw_file="${out_file}.raw.$$"
    dec_file="${out_file}.dec.$$"

    for attempt in 1 2 3; do
        if wget -q -O "$raw_file" --timeout=10 --no-check-certificate --user-agent="v2rayNG" "$sub_url" 2>/dev/null && [ -s "$raw_file" ]; then
            break
        fi
        rm -f "$raw_file"
        [ "$attempt" -lt 3 ] && { log "Download attempt $attempt failed, retrying: $sub_url" "debug"; sleep 2; }
    done

    if [ ! -s "$raw_file" ]; then
        rm -f "$raw_file" "$dec_file"
        log "Failed to download subscription after 3 attempts: $sub_url" "warn"
        return 1
    fi

    local norm_file="${out_file}.norm.$$"
    tr '_-' '/+' < "$raw_file" > "$norm_file" 2>/dev/null || cp "$raw_file" "$norm_file"
    case $(($(wc -c < "$norm_file" 2>/dev/null || echo 0) % 4)) in
        2) printf '==' >> "$norm_file" ;;
        3) printf '=' >> "$norm_file" ;;
    esac
    if base64 -d "$norm_file" > "$dec_file" 2>/dev/null && grep -q '://' "$dec_file" 2>/dev/null; then
        :
    elif base64 -d "$raw_file" > "$dec_file" 2>/dev/null && grep -q '://' "$dec_file" 2>/dev/null; then
        :
    else
        cp "$raw_file" "$dec_file"
    fi
    rm -f "$norm_file"

    # Pass 1: normalize + scheme filtering (single awk pass, no DNS).
    local prepared_file="${out_file}.prepared.$$"
    local hosts_file="${out_file}.hosts.$$"
    if ! _sl_sub_prepare_stream "$dec_file" "$prepared_file" "$idx"; then
        # A parser failure must not look like an empty subscription: report a
        # fetch failure so callers keep using the previous cache.
        log "Failed to parse subscription content: $sub_url" "warn"
        rm -f "$raw_file" "$dec_file" "$prepared_file" "$hosts_file"
        return 1
    fi
    local prepared_count
    prepared_count="$(wc -l < "$prepared_file" 2>/dev/null || echo 0)"
    case "$prepared_count" in *[!0-9]*) prepared_count=0 ;; esac
    idx=$((idx + prepared_count))
    # Candidate links in the source content (for the per-source counters).
    SL_SUB_FETCH_TOTAL="$(grep -c '://' "$dec_file" 2>/dev/null || echo 0)"
    case "$SL_SUB_FETCH_TOTAL" in *[!0-9]*) SL_SUB_FETCH_TOTAL=0 ;; esac
    local appended=0 skipped=0

    # Resolve all unique hosts in parallel batches before the per-link checks.
    cut -f3 "$prepared_file" 2>/dev/null | grep -v '^$' | sort -u > "$hosts_file"
    sl_sub_resolve_batch "$hosts_file" "$resolve_cache"

    # Pass 2: append links whose hosts resolved.
    local p_url p_title p_host
    while IFS="$TAB" read -r p_url p_title p_host || [ -n "$p_url" ]; do
        [ -z "$p_url" ] && continue
        if sl_sub_host_resolvable_cached "$p_host" "$resolve_cache"; then
            printf '%s\t%s\t%s\t%s\n' "$p_url" "$p_title" "$p_host" "$src_idx" >> "$out_file"
            appended=1
        else
            skipped=$((skipped + 1))
            log "Skipping unresolvable host '$p_host': $p_title" "debug"
        fi
    done < "$prepared_file"
    rm -f "$prepared_file" "$hosts_file"

    [ "$skipped" -gt 0 ] && log "Skipped $skipped server(s) with unresolvable hosts" "debug"
    rm -f "$raw_file" "$dec_file"
    [ "$appended" -eq 1 ] && return 0
    return 2
}

# Record last-update timestamp for a source (keyed by hash).
# Args: <hash>
sl_sub_mark_time() {
    local key="$1" ts
    ts="$(date +%s)"
    local times_file="${STATE_SOURCE_TIMES}.$$"
    : > "$times_file"
    if [ -s "$STATE_SOURCE_TIMES" ]; then
        grep -v "^${key}${TAB}" "$STATE_SOURCE_TIMES" > "$times_file" 2>/dev/null || :
    fi
    printf '%s\t%s\n' "$key" "$ts" >> "$times_file"
    mv "$times_file" "$STATE_SOURCE_TIMES"
}

# Get last-update timestamp for a source (keyed by hash).
# Args: <hash>
sl_sub_get_time() {
    local key="$1"
    [ -s "$STATE_SOURCE_TIMES" ] || { echo 0; return; }
    local ts
    ts="$(awk -F "$TAB" -v k="$key" '$1==k{print $2; exit}' "$STATE_SOURCE_TIMES" 2>/dev/null)"
    echo "${ts:-0}"
}

# Last fetched candidate count for a source (keyed by hash).
_sl_sub_total_get() {
    local key="$1" t
    [ -s "$STATE_SOURCE_TOTALS" ] || { echo 0; return; }
    t="$(awk -F "$TAB" -v k="$key" '$1==k{print $2; exit}' "$STATE_SOURCE_TOTALS" 2>/dev/null)"
    sl_safe_num "$t"
}

_sl_sub_total_set() {
    local key="$1" total="$2" tmp="${STATE_SOURCE_TOTALS}.$$"
    : > "$tmp" || return 0
    if [ -s "$STATE_SOURCE_TOTALS" ]; then
        grep -v "^${key}${TAB}" "$STATE_SOURCE_TOTALS" > "$tmp" 2>/dev/null || :
    fi
    printf '%s\t%s\n' "$key" "$total" >> "$tmp"
    mv "$tmp" "$STATE_SOURCE_TOTALS"
}

# Rebuild links from caches + fetch only sources without cache.
# Args: <out_file> [changed_hashes_comma_separated]
# Sets: SL_FETCH_COUNT, SL_FETCH_OK.
sl_sub_rebuild() {
    local out_file="$1" changed="$2"
    local work="${out_file}.work"
    local excluded_work="${out_file}.excluded.work"
    local resolve_cache="${out_file}.resolve.$$"
    : > "$work"
    : > "$excluded_work"
    : > "$resolve_cache"
    SL_FETCH_EMPTY_ACTIVE=0

    local sources
    sources="$(sl_source_list)"
    [ -z "$sources" ] && { SL_FETCH_OK=0; SL_FETCH_COUNT=0; SL_EXCLUDED_COUNT=0; SL_FETCH_EMPTY_ACTIVE=0; rm -f "$work" "$excluded_work" "$resolve_cache"; return 1; }

    local idx=1 any_src=0 src_idx=0 hard_fail=0
    mkdir -p "$STATE_SUB_CACHE"

    # Per-source counters for this rebuild: "<src_idx>\t<source_url>\t<total>".
    local idx_meta="${STATE_DIR}/idx_meta.$$"
    : > "$idx_meta"

    local line src_type need_fetch url_hash cache_file exclude_filter
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | sed 's/\r//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        src_type="$(sl_source_type "$line")"
        url_hash="$(sl_sub_hash "$line")"
        cache_file="${STATE_SUB_CACHE}/sub_${url_hash}"
        exclude_filter="$(sl_filter_normalize "$(uci -q get "$SL_NAME.main.exclude_${url_hash}" 2>/dev/null)")"

        # Only fetch if this hash is in changed list (or no changed list = scheduled full refresh).
        # A non-empty list with no matching hashes means rebuild from cache, fetching only missing caches.
        need_fetch=1
        if [ -n "$changed" ]; then
            need_fetch=0
            case ",$changed," in
                *,"$url_hash",*) need_fetch=1 ;;
            esac
        fi

        if [ "$src_type" = "manual" ]; then
            # Direct link — always process (instant, no download)
            local manual_tmp="${STATE_DIR}/manual_${url_hash}.$$"
            : > "$manual_tmp"
            if sl_sub_process_link "$line" "$manual_tmp" "$idx" "$src_idx" "$resolve_cache"; then
                sl_sub_apply_user_filter_file "$manual_tmp" "$work" "$excluded_work" "$exclude_filter"
                idx=$((idx + 1))
                any_src=1
            fi
            rm -f "$manual_tmp"
            printf '%s\t%s\t%s\n' "$src_idx" "$line" 1 >> "$idx_meta"
            sl_sub_mark_time "$url_hash"
        else
            if [ "$need_fetch" = "1" ] || [ ! -s "$cache_file" ]; then
                # Fetch this source into a temp file, then merge
                local src_tmp="${STATE_DIR}/src_${url_hash}.tmp"
                : > "$src_tmp"
                sl_sub_fetch_one "$line" "$src_tmp" "$idx" "$src_idx" "$resolve_cache"
                local fetch_rc=$?
                if [ "$fetch_rc" -eq 0 ]; then
                    sl_sub_apply_user_filter_file "$src_tmp" "$work" "$excluded_work" "$exclude_filter"
                    cut -f1-3 "$src_tmp" > "${cache_file}.new" 2>/dev/null
                    mv "${cache_file}.new" "$cache_file" 2>/dev/null
                    _sl_sub_total_set "$url_hash" "${SL_SUB_FETCH_TOTAL:-0}"
                    printf '%s\t%s\t%s\n' "$src_idx" "$line" "${SL_SUB_FETCH_TOTAL:-0}" >> "$idx_meta"
                    any_src=1
                    sl_sub_mark_time "$url_hash"
                elif [ "$fetch_rc" -eq 2 ]; then
                    log "Subscription has no usable servers, clearing cache for: $line" "warn"
                    rm -f "$cache_file" "${cache_file}.new" 2>/dev/null
                    printf '%s\t%s\t%s\n' "$src_idx" "$line" "${SL_SUB_FETCH_TOTAL:-0}" >> "$idx_meta"
                    sl_sub_mark_time "$url_hash"
                elif [ -s "$cache_file" ]; then
                    log "Sub fetch failed, using cache for: $line" "warn"
                    local cache_tmp="${STATE_DIR}/cache_${url_hash}.$$"
                    awk -v si="$src_idx" -F "$TAB" '{print $1"\t"$2"\t"$3"\t"si}' "$cache_file" > "$cache_tmp"
                    sl_sub_apply_user_filter_file "$cache_tmp" "$work" "$excluded_work" "$exclude_filter"
                    rm -f "$cache_tmp"
                    printf '%s\t%s\t%s\n' "$src_idx" "$line" "$(_sl_sub_total_get "$url_hash")" >> "$idx_meta"
                    any_src=1
                else
                    log "Sub fetch failed and no cache: $line" "warn"
                    hard_fail=1
                fi
                rm -f "$src_tmp"
            elif [ -s "$cache_file" ]; then
                # Use cache, don't re-download
                sl_sub_cache_normalize "$cache_file" || {
                    log "Failed to normalize subscription cache: $line" "warn"
                }
                local cache_tmp="${STATE_DIR}/cache_${url_hash}.$$"
                awk -v si="$src_idx" -F "$TAB" '{print $1"\t"$2"\t"$3"\t"si}' "$cache_file" > "$cache_tmp"
                sl_sub_apply_user_filter_file "$cache_tmp" "$work" "$excluded_work" "$exclude_filter"
                rm -f "$cache_tmp"
                printf '%s\t%s\t%s\n' "$src_idx" "$line" "$(_sl_sub_total_get "$url_hash")" >> "$idx_meta"
                any_src=1
            fi
            idx=$((idx + 10000))
        fi
        src_idx=$((src_idx + 1))
    done <<EOF
$sources
EOF

    [ "$hard_fail" -eq 1 ] && { SL_FETCH_OK=0; SL_FETCH_COUNT=0; SL_EXCLUDED_COUNT=0; SL_FETCH_EMPTY_ACTIVE=0; rm -f "$work" "$excluded_work" "$resolve_cache" "$idx_meta"; return 1; }
    [ "$any_src" -ne 1 ] && { SL_FETCH_OK=0; SL_FETCH_COUNT=0; SL_EXCLUDED_COUNT=0; SL_FETCH_EMPTY_ACTIVE=0; rm -f "$work" "$excluded_work" "$resolve_cache" "$idx_meta"; return 1; }

    # Dedupe active rows first (unique links are also probed once), then let
    # the installed engine veto links it cannot use.
    awk -F "$TAB" '!seen[$1]++' "$work" > "${work}.uniq"
    sl_sub_engine_gate "${work}.uniq" "$out_file" "${work}.gate_skipped"
    local gate_skipped_count=0
    while IFS="$TAB" read -r g_url g_title g_reason || [ -n "$g_url" ]; do
        [ -n "$g_url" ] || continue
        gate_skipped_count=$((gate_skipped_count + 1))
        log "Engine rejected '$g_title': $g_reason" "debug"
    done < "${work}.gate_skipped"
    [ "$gate_skipped_count" -gt 0 ] && log "Filtered $gate_skipped_count link(s) unusable by the engine" "debug"

    awk -F "$TAB" '!seen[$1 FS $4]++' "$excluded_work" > "${out_file}.excluded"

    # Per-source counters: candidate links from the last fetch, by URL.
    local stats_tmp="${STATE_SOURCE_STATS}.$$" m_idx m_url m_total
    : > "$stats_tmp"
    while IFS="$TAB" read -r m_idx m_url m_total || [ -n "$m_idx" ]; do
        [ -n "$m_url" ] || continue
        printf '%s\t%s\n' "$m_url" "$(sl_safe_num "$m_total")" >> "$stats_tmp"
    done < "$idx_meta"
    mv "$stats_tmp" "$STATE_SOURCE_STATS" 2>/dev/null
    rm -f "$work" "${work}.uniq" "${work}.gate_skipped" "$excluded_work" "$resolve_cache" "$idx_meta"
    SL_FETCH_COUNT="$(wc -l < "$out_file" 2>/dev/null || echo 0)"
    SL_EXCLUDED_COUNT="$(wc -l < "${out_file}.excluded" 2>/dev/null || echo 0)"
    if [ "$(sl_safe_num "$SL_FETCH_COUNT")" -le 0 ]; then
        log "No active servers left after subscription filters" "warn"
        SL_FETCH_EMPTY_ACTIVE=1
        SL_FETCH_OK=0
        return 1
    fi
    SL_FETCH_OK=1
    return 0
}
