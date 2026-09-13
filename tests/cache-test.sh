#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/omarchy-github-fetch"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir "$sandbox/bin"
export GH_TEST_LOG="$sandbox/gh.log"
export GH_SCENARIO=ready
export GH_GUARD="$sandbox/api-active"
: >"$GH_TEST_LOG"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_jq() { jq -e "$1" <<<"$2" >/dev/null || fail "$3"; }
api_count() { grep -c ':api' "$GH_TEST_LOG" 2>/dev/null || true; }
auth_count() { grep -c ':auth token' "$GH_TEST_LOG" 2>/dev/null || true; }

cat >"$sandbox/bin/gh" <<'GH'
#!/usr/bin/env bash
set -u
printf '%s:%s\n' "${GH_SCENARIO:-ready}" "$*" >>"$GH_TEST_LOG"
if [[ $1 == auth && $2 == token ]]; then
  if [[ ${GH_SCENARIO:-} == interrupt ]]; then kill -TERM "$PPID"; sleep 1; fi
  printf '%s\n' 'ghp_test_token_that_must_not_be_saved'
  exit 0
fi
[[ $1 == api ]] || exit 1
if ! mkdir "$GH_GUARD" 2>/dev/null; then printf 'overlap\n' >>"$GH_TEST_LOG"; else trap 'rmdir "$GH_GUARD" 2>/dev/null || :' EXIT; fi
[[ ${GH_SCENARIO:-} != concurrent ]] || sleep 0.08
if [[ $2 == --include && $3 == /rate_limit ]]; then
  case ${GH_SCENARIO:-ready} in
    rate) printf 'HTTP/2.0 429 Too Many Requests\nX-RateLimit-Remaining: 42\nX-RateLimit-Reset: 2600\nRetry-After: 120\n\n{"message":"secondary rate limit"}\n'; exit 1 ;;
    rate403) printf 'HTTP/2.0 403 Forbidden\nX-RateLimit-Remaining: 0\nX-RateLimit-Reset: 2600\n\n{"message":"API rate limit exceeded"}\n'; exit 1 ;;
    unauthorized) printf 'HTTP/2.0 401 Unauthorized\n\n{"message":"Bad credentials"}\n'; exit 1 ;;
    transient) printf 'connection reset by peer\n' >&2; exit 1 ;;
  esac
  printf 'HTTP/2.0 200 OK\nX-RateLimit-Remaining: 42\nX-RateLimit-Reset: 1893456000\n\n{"resources":{"core":{"remaining":42,"reset":1893456000}}}\n'
  exit 0
fi
case ${GH_SCENARIO:-ready} in
  rest-rate) printf 'HTTP 429: secondary rate limit\n' >&2; exit 1 ;;
esac
if [[ $2 == graphql && $* == *author:@me* ]]; then
  printf '%s\n' '{"data":{"search":{"issueCount":0,"nodes":[]}}}'
elif [[ $2 == graphql ]]; then
  printf '%s\n' '{"data":{"viewer":{"login":"octocat","repositories":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"remaining":42,"resetAt":"2030-01-01T00:00:00Z","cost":1}}}'
else
  endpoint=${*: -1}
  if [[ $endpoint == /search/issues* ]]; then printf '%s\n' '{"items":[]}'
  else printf '%s\n' '[]'
  fi
fi
GH
chmod +x "$sandbox/bin/gh"
run() { PATH="$sandbox/bin:$PATH" "$HELPER" --action-scan off --include-contributions false "$@"; }

# A ready manual scan seeds a private, bounded cache.
export XDG_CACHE_HOME="$sandbox/cache-main"
out=$(OMARCHY_GITHUB_NOW=1000 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and .login == "octocat"' "$out" "ready seed scan"
[[ $(stat -c %a "$XDG_CACHE_HOME/omarchy-github") == 700 ]] || fail "cache directory is not private"
[[ $(stat -c %a "$XDG_CACHE_HOME/omarchy-github/dashboard.json") == 600 ]] || fail "cache file is not private"
if grep -R 'ghp_test_token' "$XDG_CACHE_HOME" >/dev/null; then fail "credential was persisted"; fi

# Recreated automatic services inside the interval restore cache without even a
# local credential lookup; a manual refresh bypasses only this freshness gate.
: >"$GH_TEST_LOG"
auto_one=$(OMARCHY_GITHUB_NOW=1100 run --automatic --refresh-interval 300)
auto_two=$(OMARCHY_GITHUB_NOW=1100 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and .login == "octocat"' "$auto_one" "automatic cache restore"
assert_jq '.state == "ready" and .login == "octocat"' "$auto_two" "repeated automatic startup"
[[ ! -s $GH_TEST_LOG ]] || fail "fresh automatic startup touched credentials or network"
manual=$(OMARCHY_GITHUB_NOW=1100 run)
assert_jq '.state == "ready"' "$manual" "manual freshness bypass"
[[ $(api_count) -gt 0 ]] || fail "manual refresh did not bypass ordinary freshness"

# Confirmed response classes stay distinct from missing local credentials.
for scenario in rate rate403 rest-rate unauthorized transient; do
  export XDG_CACHE_HOME="$sandbox/cache-$scenario" GH_SCENARIO=$scenario
  : >"$GH_TEST_LOG"
  result=$(OMARCHY_GITHUB_NOW=2000 run)
  case $scenario in
    rate) assert_jq '.state == "rate-limited" and .rateLimit.resetAt == "1970-01-01T00:35:20Z"' "$result" "429 Retry-After deadline" ;;
    rate403) assert_jq '.state == "rate-limited" and .rateLimit.resetAt == "1970-01-01T00:43:20Z"' "$result" "exact server reset deadline" ;;
    rest-rate) assert_jq '.state == "rate-limited" and (.rateLimit.resetAt? == null)' "$result" "headerless REST failure hides the local fallback" ;;
    unauthorized) assert_jq '.state == "invalid-credentials"' "$result" "401 classification" ;;
    transient) assert_jq '.state == "error"' "$result" "transient classification" ;;
  esac
done
assert_jq '.rateLimitUntil == 2600 and .rateLimitResetKnown == true' "$(cat "$sandbox/cache-rate403/omarchy-github/refresh-state.json")" "exact server reset persistence"
assert_jq '.rateLimitUntil == 2060 and .rateLimitResetKnown == false' "$(cat "$sandbox/cache-rest-rate/omarchy-github/refresh-state.json")" "undisplayed conservative fallback persistence"

# The exact server deadline blocks both scan modes before credentials or API.
export XDG_CACHE_HOME="$sandbox/cache-rate403" GH_SCENARIO=ready
: >"$GH_TEST_LOG"
blocked_auto=$(OMARCHY_GITHUB_NOW=2599 run --automatic --refresh-interval 300)
blocked_manual=$(OMARCHY_GITHUB_NOW=2599 run)
assert_jq '.state == "rate-limited" and .rateLimit.resetAt == "1970-01-01T00:43:20Z"' "$blocked_auto" "persisted automatic server reset"
assert_jq '.state == "rate-limited" and .rateLimit.resetAt == "1970-01-01T00:43:20Z"' "$blocked_manual" "persisted manual server reset"
[[ $(api_count) -eq 0 && $(auth_count) -eq 0 ]] || fail "persisted server reset touched credentials or API before expiry"
: >"$GH_TEST_LOG"
after_reset=$(OMARCHY_GITHUB_NOW=2601 run)
assert_jq '.state == "ready"' "$after_reset" "manual refresh after server reset"
[[ $(api_count) -gt 0 ]] || fail "server reset remained active after expiry"

# The next automatic attempt is durable before the first network call. Simulate
# interruption during the first local token read, then recreate immediately.
export XDG_CACHE_HOME="$sandbox/cache-interrupt" GH_SCENARIO=interrupt
: >"$GH_TEST_LOG"
set +e
OMARCHY_GITHUB_NOW=3000 run --automatic --refresh-interval 300 >/dev/null 2>&1
set -e
export GH_SCENARIO=ready
recreated=$(OMARCHY_GITHUB_NOW=3000 run --automatic --refresh-interval 300)
assert_jq '.state == "waiting"' "$recreated" "interrupted first attempt scheduling"
[[ $(api_count) -eq 0 && $(auth_count) -eq 1 ]] || fail "interrupted automatic scan repeated immediately"

# Two full scans may both run, but their network sections must not overlap.
export XDG_CACHE_HOME="$sandbox/cache-concurrent" GH_SCENARIO=concurrent
: >"$GH_TEST_LOG"
OMARCHY_GITHUB_NOW=4000 run >"$sandbox/one.json" & one=$!
OMARCHY_GITHUB_NOW=4000 run >"$sandbox/two.json" & two=$!
wait "$one"; wait "$two"
assert_jq '.state == "ready"' "$(cat "$sandbox/one.json")" "first concurrent scan"
assert_jq '.state == "ready"' "$(cat "$sandbox/two.json")" "second concurrent scan"
if grep -q '^overlap$' "$GH_TEST_LOG"; then fail "full fetch lock allowed overlap"; fi

echo "cache and refresh tests passed"
