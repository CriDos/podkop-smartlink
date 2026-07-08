# shellcheck disable=SC2034

## SmartLink
SL_VERSION="1.2.0"
SL_NAME="podkop-smartlink"

# Podkop integration
PODKOP_BIN="/usr/bin/podkop"
PODKOP_SECTION_DEFAULT="main"

# State in /tmp (survives daemon restart, not reboot)
STATE_DIR="/tmp/podkop-smartlink"
STATE_CURRENT="$STATE_DIR/current"
STATE_LINKS_CACHE="$STATE_DIR/links.cache"
STATE_LINKS_FULL="$STATE_DIR/links.full"
STATE_LINKS_EXCLUDED="$STATE_DIR/links.excluded"
STATE_TAGS_CACHE="$STATE_DIR/tags.cache"
STATE_HISTORY_DIR="$STATE_DIR/history"
STATE_STATUS="$STATE_DIR/status.json"
STATE_LAST_UPDATE="$STATE_DIR/last_update"
STATE_LAST_PING="$STATE_DIR/last_ping"
STATE_SOURCE_TIMES="$STATE_DIR/source_times"
STATE_PID="/var/run/podkop-smartlink.pid"
STATE_SUB_CACHE="$STATE_DIR/sub_cache"
STATE_SYNC_LOCK="$STATE_DIR/sync.lock"
STATE_REFRESH_LOCK="$STATE_DIR/refresh.lock"
STATE_REFRESH_RESULT="$STATE_DIR/refresh_result"

# Clash API (sing-box experimental clash_api)
CLASH_API_PORT=9090
CLASH_API_READY_MAX_WAIT=60
CLASH_API_READY_POLL=1

# Defaults
DEFAULT_UPDATE_INTERVAL="24h"
DEFAULT_CHECK_INTERVAL=10
DEFAULT_MAX_PING=500
DEFAULT_FAIL_COUNT=3
DEFAULT_PING_TIMEOUT=2000
DEFAULT_STATS_PING_INTERVAL=300
DEFAULT_TEST_URL="http://cp.cloudflare.com"
DEFAULT_USE_PRIORITY=0

# History sample cap (for stability calc, kept per URL)
HISTORY_MAX_SAMPLES=100

# Transports supported by standard sing-box (without extended build)
SUPPORTED_TRANSPORTS="tcp raw ws grpc http"
