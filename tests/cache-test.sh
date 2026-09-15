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
export GH_TEST_TOKEN=ghp_test_token_a_that_must_not_be_saved
export GH_TEST_LOGIN=octocat
: >"$GH_TEST_LOG"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_jq() { jq -e "$1" <<<"$2" >/dev/null || fail "$3"; }
api_count() { grep -c ':api' "$GH_TEST_LOG" 2>/dev/null || true; }
auth_count() { grep -c ':auth token' "$GH_TEST_LOG" 2>/dev/null || true; }
replace_cache_jq() {
  local filter=$1 cache="$XDG_CACHE_HOME/omarchy-github/dashboard.json" next="$sandbox/dashboard.next"
  jq "$filter" "$cache" >"$next"
  chmod 600 "$next"
  mv "$next" "$cache"
}

cat >"$sandbox/bin/gh" <<'GH'
#!/usr/bin/env bash
set -u
printf '%s:%s\n' "${GH_SCENARIO:-ready}" "$*" >>"$GH_TEST_LOG"
if [[ $1 == auth && $2 == token ]]; then
  [[ ${GH_SCENARIO:-} != logged-out ]] || exit 1
  printf '%s\n' "${GH_TEST_TOKEN:-ghp_test_token_a_that_must_not_be_saved}"
  exit 0
fi
[[ $1 == api ]] || exit 1
if ! mkdir "$GH_GUARD" 2>/dev/null; then printf 'overlap\n' >>"$GH_TEST_LOG"; else trap 'rmdir "$GH_GUARD" 2>/dev/null || :' EXIT; fi
[[ ${GH_SCENARIO:-} != concurrent ]] || sleep 0.08
if [[ ${GH_SCENARIO:-} == interrupt-bulk && $2 == --method && $3 == PUT && $4 == /notifications ]]; then
  kill -TERM "$PPID"
  exit 143
fi
if [[ $2 == --include && $3 == /rate_limit ]]; then
  case ${GH_SCENARIO:-ready} in
    interrupt) kill -TERM "$PPID"; sleep 1; exit 1 ;;
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
  api_login=${GH_TEST_LOGIN:-octocat}
  if [[ ${GH_SCENARIO:-} == switch-during-scan && ${GH_TOKEN:-} != "${GH_TEST_TOKEN:-}" ]]; then api_login=other-account; fi
  jq -n --arg login "$api_login" '{data:{viewer:{login:$login,repositories:{nodes:[],pageInfo:{hasNextPage:false,endCursor:null}}},rateLimit:{remaining:42,resetAt:"2030-01-01T00:00:00Z",cost:1}}}'
else
  endpoint=${*: -1}
  if [[ $endpoint == /search/issues* ]]; then printf '%s\n' '{"items":[]}'
  else printf '%s\n' '[]'
  fi
fi
GH
chmod +x "$sandbox/bin/gh"
run() { env -u GH_TOKEN -u GITHUB_TOKEN PATH="$sandbox/bin:$PATH" "$HELPER" --action-scan off --include-contributions false "$@"; }
run_with_token() { local token=$1; shift; GH_TOKEN="$token" GITHUB_TOKEN='' PATH="$sandbox/bin:$PATH" "$HELPER" --action-scan off --include-contributions false "$@"; }

# A ready scan seeds a private, bounded cache whose state contains only hashes,
# never the credential itself.
export XDG_CACHE_HOME="$sandbox/cache-main"
out=$(OMARCHY_GITHUB_NOW=1000 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and .login == "octocat"' "$out" "ready seed scan"
[[ $(stat -c %a "$XDG_CACHE_HOME/omarchy-github") == 700 ]] || fail "cache directory is not private"
[[ $(stat -c %a "$XDG_CACHE_HOME/omarchy-github/dashboard.json") == 600 ]] || fail "cache file is not private"
state=$(cat "$XDG_CACHE_HOME/omarchy-github/refresh-state.json")
assert_jq '.schemaVersion == 2 and (.credentialFingerprint|test("^[0-9a-f]{64}$")) and (.policyFingerprint|test("^[0-9a-f]{64}$"))' "$state" "cache context fingerprints"
if grep -R "$GH_TEST_TOKEN" "$XDG_CACHE_HOME" >/dev/null; then fail "credential was persisted"; fi

# Recreated services inside the interval may read the local credential identity,
# but still restore cache without any GitHub API request.
: >"$GH_TEST_LOG"
auto_one=$(OMARCHY_GITHUB_NOW=1100 run --automatic --refresh-interval 300)
auto_two=$(OMARCHY_GITHUB_NOW=1100 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and .login == "octocat"' "$auto_one" "automatic cache restore"
assert_jq '.state == "ready" and .login == "octocat"' "$auto_two" "repeated automatic startup"
[[ $(api_count) -eq 0 && $(auth_count) -eq 2 ]] || fail "fresh automatic startup crossed its network gate"
manual=$(OMARCHY_GITHUB_NOW=1100 run)
assert_jq '.state == "ready"' "$manual" "manual freshness bypass"
[[ $(api_count) -gt 0 ]] || fail "manual refresh did not bypass ordinary freshness"

# A cache is never presented under missing or different credentials.
: >"$GH_TEST_LOG"
export GH_SCENARIO=logged-out
logged_out=$(OMARCHY_GITHUB_NOW=1150 run --automatic --refresh-interval 300)
assert_jq '.state == "logged-out" and .login == "" and (.repositories|length) == 0' "$logged_out" "logged-out cache isolation"
[[ $(api_count) -eq 0 && $(auth_count) -eq 1 ]] || fail "logged-out cache check touched the API"
export GH_SCENARIO=ready GH_TEST_TOKEN=ghp_test_token_b_that_must_not_be_saved GH_TEST_LOGIN=other-account
: >"$GH_TEST_LOG"
switched=$(OMARCHY_GITHUB_NOW=1150 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and .login == "other-account"' "$switched" "account switch refresh"
[[ $(api_count) -gt 0 ]] || fail "account switch reused the previous account cache"
export GH_TEST_TOKEN=ghp_test_token_a_that_must_not_be_saved GH_TEST_LOGIN=octocat

# Environment credentials have precedence in gh and therefore in cache identity.
export XDG_CACHE_HOME="$sandbox/cache-env-token"
OMARCHY_GITHUB_NOW=2000 run --automatic --refresh-interval 300 >/dev/null
: >"$GH_TEST_LOG"
GH_TEST_LOGIN=environment-account run_with_token ghp_environment_token_b_that_must_not_be_saved --automatic --refresh-interval 300 >"$sandbox/environment-account.json"
assert_jq '.state == "ready" and .login == "environment-account"' "$(cat "$sandbox/environment-account.json")" "environment token cache isolation"
[[ $(api_count) -gt 0 && $(auth_count) -eq 0 ]] || fail "environment token did not take precedence over stored credentials"

# A credential switch during a scan cannot change the account used by API calls.
export XDG_CACHE_HOME="$sandbox/cache-switch-race" GH_SCENARIO=switch-during-scan
: >"$GH_TEST_LOG"
pinned=$(OMARCHY_GITHUB_NOW=2500 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and .login == "octocat"' "$pinned" "credential pinned for complete scan"
export GH_SCENARIO=ready

# Output-shaping options are part of the cache identity.
export XDG_CACHE_HOME="$sandbox/cache-policy"
OMARCHY_GITHUB_NOW=3000 run --automatic --refresh-interval 300 --repository-scope organizations >/dev/null
: >"$GH_TEST_LOG"
policy_changed=$(OMARCHY_GITHUB_NOW=3100 run --automatic --refresh-interval 300 --repository-scope owned)
assert_jq '.state == "ready" and .repositoryScope == "owned"' "$policy_changed" "repository policy cache isolation"
[[ $(api_count) -gt 0 ]] || fail "incompatible repository policy reused cache"

# Freshness is calculated from the current interval, not an old derived deadline.
export XDG_CACHE_HOME="$sandbox/cache-shorter"
OMARCHY_GITHUB_NOW=4000 run --automatic --refresh-interval 900 >/dev/null
: >"$GH_TEST_LOG"
OMARCHY_GITHUB_NOW=4100 run --automatic --refresh-interval 60 >/dev/null
[[ $(api_count) -gt 0 ]] || fail "shorter refresh interval kept the old deadline"
export XDG_CACHE_HOME="$sandbox/cache-longer"
OMARCHY_GITHUB_NOW=5000 run --automatic --refresh-interval 60 >/dev/null
: >"$GH_TEST_LOG"
longer=$(OMARCHY_GITHUB_NOW=5061 run --automatic --refresh-interval 900)
assert_jq '.state == "ready"' "$longer" "longer refresh interval cache restore"
[[ $(api_count) -eq 0 && $(auth_count) -eq 1 ]] || fail "longer refresh interval refreshed too early"

# Confirmed response classes stay distinct from missing local credentials.
for scenario in rate rate403 rest-rate unauthorized transient; do
  export XDG_CACHE_HOME="$sandbox/cache-$scenario" GH_SCENARIO=$scenario
  : >"$GH_TEST_LOG"
  result=$(OMARCHY_GITHUB_NOW=2000 run)
  case $scenario in
    rate) assert_jq '.state == "rate-limited" and .rateLimit.remaining == 42 and .rateLimit.resetAt == "1970-01-01T00:35:20Z" and (.rateLimit.cost? == null)' "$result" "429 Retry-After deadline" ;;
    rate403) assert_jq '.state == "rate-limited" and .rateLimit.remaining == 0 and .rateLimit.resetAt == "1970-01-01T00:43:20Z" and (.rateLimit.cost? == null)' "$result" "exact server reset deadline" ;;
    rest-rate) assert_jq '.state == "rate-limited" and .rateLimit.remaining == 42 and (.rateLimit.cost? == null) and (.rateLimit.resetAt? == null)' "$result" "headerless REST failure uses current preflight quota" ;;
    unauthorized) assert_jq '.state == "invalid-credentials"' "$result" "401 classification" ;;
    transient) assert_jq '.state == "error"' "$result" "transient classification" ;;
  esac
done
assert_jq '.schemaVersion == 2 and .rateLimitUntil == 2600 and .rateLimitResetKnown == true and .rateLimitRemaining == 0 and .rateLimitCost == -1' "$(cat "$sandbox/cache-rate403/omarchy-github/refresh-state.json")" "exact server reset persistence"
assert_jq '.rateLimitUntil == 2060 and .rateLimitResetKnown == false and .rateLimitRemaining == 42 and .rateLimitCost == -1' "$(cat "$sandbox/cache-rest-rate/omarchy-github/refresh-state.json")" "undisplayed conservative fallback persistence"

# Persisted rate state belongs only to the credential that observed it.
export XDG_CACHE_HOME="$sandbox/cache-rate-account" GH_SCENARIO=rate403
OMARCHY_GITHUB_NOW=2000 run >/dev/null
export GH_SCENARIO=ready GH_TEST_TOKEN=ghp_test_token_b_that_must_not_be_saved GH_TEST_LOGIN=other-account
: >"$GH_TEST_LOG"
other_rate_account=$(OMARCHY_GITHUB_NOW=2050 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and .login == "other-account"' "$other_rate_account" "rate state account isolation"
[[ $(api_count) -gt 0 ]] || fail "new account inherited the old account rate wait"
export GH_TEST_TOKEN=ghp_test_token_a_that_must_not_be_saved GH_TEST_LOGIN=octocat

# A current exhausted preflight replaces every stale quota field in cached data.
export XDG_CACHE_HOME="$sandbox/cache-stale-rate" GH_SCENARIO=ready
OMARCHY_GITHUB_NOW=1800 run --automatic --refresh-interval 300 >/dev/null
replace_cache_jq '.rateLimit={remaining:999,cost:77,resetAt:"2030-01-01T00:00:00Z"}'
export GH_SCENARIO=rate403
stale_rate=$(OMARCHY_GITHUB_NOW=2000 run)
assert_jq '.state == "rate-limited" and .preserveDashboard == true and .rateLimit == {remaining:0,resetAt:"1970-01-01T00:43:20Z"}' "$stale_rate" "stale cached quota replacement"

# The exact server deadline blocks both scan modes before any API request.
export XDG_CACHE_HOME="$sandbox/cache-rate403" GH_SCENARIO=ready
: >"$GH_TEST_LOG"
blocked_auto=$(OMARCHY_GITHUB_NOW=2599 run --automatic --refresh-interval 300)
blocked_manual=$(OMARCHY_GITHUB_NOW=2599 run)
assert_jq '.state == "rate-limited" and .rateLimit.remaining == 0 and .rateLimit.resetAt == "1970-01-01T00:43:20Z"' "$blocked_auto" "persisted automatic server reset"
assert_jq '.state == "rate-limited" and .rateLimit.remaining == 0 and .rateLimit.resetAt == "1970-01-01T00:43:20Z"' "$blocked_manual" "persisted manual server reset"
[[ $(api_count) -eq 0 && $(auth_count) -eq 2 ]] || fail "persisted server reset touched the API before expiry"
: >"$GH_TEST_LOG"
after_reset=$(OMARCHY_GITHUB_NOW=2601 run)
assert_jq '.state == "ready"' "$after_reset" "manual refresh after server reset"
[[ $(api_count) -gt 0 ]] || fail "server reset remained active after expiry"

# The attempt timestamp is durable before the first network request. Interrupt
# the preflight, then recreate immediately without allowing a second API call.
export XDG_CACHE_HOME="$sandbox/cache-interrupt" GH_SCENARIO=interrupt
: >"$GH_TEST_LOG"
set +e
OMARCHY_GITHUB_NOW=6000 run --automatic --refresh-interval 300 >/dev/null 2>&1
set -e
export GH_SCENARIO=ready
recreated=$(OMARCHY_GITHUB_NOW=6000 run --automatic --refresh-interval 300)
assert_jq '.state == "waiting"' "$recreated" "interrupted first attempt scheduling"
[[ $(api_count) -eq 1 && $(auth_count) -eq 2 ]] || fail "interrupted automatic scan repeated its network request"

# Successful mutations invalidate freshness while holding the shared lock, so a
# crash before Service.qml's follow-up refresh cannot restore stale rows.
export XDG_CACHE_HOME="$sandbox/cache-mark-one" GH_SCENARIO=ready
OMARCHY_GITHUB_NOW=7000 run --automatic --refresh-interval 300 >/dev/null
replace_cache_jq '.notifications=[{id:"123",updatedAt:"2020-01-01T00:00:00Z"}]'
: >"$GH_TEST_LOG"
mark_one=$(run --mark-notification-read 123)
assert_jq '.state == "ready" and .notificationId == "123"' "$mark_one" "single mark success"
after_mark_one=$(OMARCHY_GITHUB_NOW=7100 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and (.notifications|length) == 0' "$after_mark_one" "single mark cache invalidation"
[[ $(api_count) -gt 1 ]] || fail "single mark restart restored cache instead of refreshing"

export XDG_CACHE_HOME="$sandbox/cache-mark-interrupted"
OMARCHY_GITHUB_NOW=8000 run --automatic --refresh-interval 300 >/dev/null
replace_cache_jq '.notifications=[{id:"124",updatedAt:"2020-01-01T00:00:00Z"}]'
export GH_SCENARIO=interrupt-bulk
: >"$GH_TEST_LOG"
set +e
run --mark-all-read-before 2020-01-01T00:00:00Z --mark-boundary-notification 124 >/dev/null 2>&1
interrupted_bulk_status=$?
set -e
[[ $interrupted_bulk_status -ne 0 ]] || fail "interrupted bulk mark returned success"
export GH_SCENARIO=ready
interrupted_bulk_restart=$(OMARCHY_GITHUB_NOW=8100 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and (.notifications|length) == 0' "$interrupted_bulk_restart" "interrupted bulk cache invalidation"
[[ $(api_count) -gt 1 ]] || fail "interrupted bulk mutation restored stale cache"

export XDG_CACHE_HOME="$sandbox/cache-mark-all"
OMARCHY_GITHUB_NOW=8200 run --automatic --refresh-interval 300 >/dev/null
replace_cache_jq '.notifications=[{id:"124",updatedAt:"2020-01-01T00:00:00Z"}]'
: >"$GH_TEST_LOG"
mark_all=$(run --mark-all-read-before 2020-01-01T00:00:00Z --mark-boundary-notification 124)
assert_jq '.state == "ready" and .lastReadAt == "2020-01-01T00:00:00Z"' "$mark_all" "bulk mark success"
after_mark_all=$(OMARCHY_GITHUB_NOW=8300 run --automatic --refresh-interval 300)
assert_jq '.state == "ready" and (.notifications|length) == 0' "$after_mark_all" "bulk mark cache invalidation"
[[ $(api_count) -gt 2 ]] || fail "bulk mark restart restored cache instead of refreshing"

# Concurrent full scans may serialize and both run, but their network sections
# must never overlap.
export XDG_CACHE_HOME="$sandbox/cache-concurrent" GH_SCENARIO=concurrent
: >"$GH_TEST_LOG"
OMARCHY_GITHUB_NOW=9000 run >"$sandbox/one.json" & one=$!
OMARCHY_GITHUB_NOW=9000 run >"$sandbox/two.json" & two=$!
wait "$one"; wait "$two"
assert_jq '.state == "ready"' "$(cat "$sandbox/one.json")" "first concurrent scan"
assert_jq '.state == "ready"' "$(cat "$sandbox/two.json")" "second concurrent scan"
if grep -q '^overlap$' "$GH_TEST_LOG"; then fail "full fetch lock allowed overlap"; fi

echo "cache and refresh tests passed"
