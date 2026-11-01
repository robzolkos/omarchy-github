#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/omarchy-github-fetch"
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir "$sandbox/bin"
export GH_TEST_LOG="$sandbox/gh.log"
export GH_TEST_ACCOUNTS="alice bob"
: >"$GH_TEST_LOG"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_jq() { jq -e "$1" <<<"$2" >/dev/null || fail "$3"; }
# The stub logs "<account owning GH_TOKEN, or - without one>:<arguments>".
calls_for() { grep -c "^$1:" "$GH_TEST_LOG" 2>/dev/null || true; }
api_calls_for() { grep -c "^$1:api" "$GH_TEST_LOG" 2>/dev/null || true; }

# Every account gets the token ghp_token_for_<login>. The helper must pin each
# per-account scan to that token, so the stub derives which account is asking
# from GH_TOKEN alone, exactly as GitHub would.
cat >"$sandbox/bin/gh" <<'GH'
#!/usr/bin/env bash
set -u
who=-
[[ -z ${GH_TOKEN:-} ]] || who=${GH_TOKEN#ghp_token_for_}
printf '%s:%s\n' "$who" "$*" >>"$GH_TEST_LOG"
if [[ $1 == auth && $2 == status ]]; then
  [[ ${GH_STATUS_FAILS:-} != true ]] || exit 1
  for login in $GH_TEST_ACCOUNTS; do echo "$login"; done |
    jq -Rn '{hosts:{"github.com":[inputs | {state:"success",active:false,host:"github.com",login:.,tokenSource:"keyring",scopes:"repo",gitProtocol:"https"}]}}'
  exit 0
fi
if [[ $1 == auth && $2 == token ]]; then
  login=
  while (($#)); do [[ $1 != --user ]] || login=${2-}; shift; done
  [[ -n $login ]] || login=${GH_TEST_ACTIVE:-alice}
  [[ $login != ghost ]] || { echo "no oauth token found for github.com account ghost" >&2; exit 1; }
  printf 'ghp_token_for_%s\n' "$login"
  exit 0
fi
[[ $1 == api ]] || exit 1
if [[ $2 == --include && $3 == /rate_limit ]]; then
  if [[ " ${GH_RATE_LIMITED:-} " == *" $who "* ]]; then
    printf 'HTTP/2.0 403 Forbidden\nX-RateLimit-Remaining: 0\nX-RateLimit-Reset: 2600\n\n{"message":"API rate limit exceeded"}\n'
    exit 1
  fi
  printf 'HTTP/2.0 200 OK\nX-RateLimit-Remaining: 42\nX-RateLimit-Reset: 1893456000\n\n{"resources":{"core":{"remaining":42,"reset":1893456000}}}\n'
  exit 0
fi
if [[ $2 == --method ]]; then
  # Thread ids belong to one account: 1xx to alice, 2xx to bob.
  case $3:$4 in
    PATCH:/notifications/threads/1??) [[ $who == alice ]] || { echo "HTTP 404: Not Found" >&2; exit 1; } ;;
    PATCH:/notifications/threads/2??) [[ $who == bob ]] || { echo "HTTP 404: Not Found" >&2; exit 1; } ;;
    PUT:/notifications) ;;
    *) exit 9 ;;
  esac
  printf '%s\n' '{}'
  exit 0
fi
if [[ $2 == graphql && $* == *author:@me* ]]; then
  if [[ $who == bob ]]; then
    printf '%s\n' '{"data":{"search":{"issueCount":3,"nodes":[{"number":3,"title":"Fix the tool","url":"https://github.com/bob/tool/pull/3","updatedAt":"2026-01-05T00:00:00Z","isDraft":false,"repository":{"nameWithOwner":"bob/tool"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}}]}}}'
  else
    printf '%s\n' '{"data":{"search":{"issueCount":0,"nodes":[]}}}'
  fi
  exit 0
fi
if [[ $2 == graphql ]]; then
  jq -n --arg login "$who" '{data:{viewer:{login:$login,repositories:{nodes:[{name:"repo",nameWithOwner:($login + "/repo"),url:("https://github.com/" + $login + "/repo"),isArchived:false,isFork:false,stargazerCount:(if $login == "bob" then 5 else 1 end),updatedAt:"2026-01-01T00:00:00Z",issues:{totalCount:0},pullRequests:{totalCount:0}}],pageInfo:{hasNextPage:false,endCursor:null}}},rateLimit:{remaining:(if $login == "bob" then 4000 else 4900 end),resetAt:"2030-01-01T00:00:00Z",cost:1}}}'
  exit 0
fi
endpoint=${*: -1}
case $endpoint:$who in
  /notifications*:alice) printf '%s\n' '[{"id":"101","unread":true,"reason":"mention","updated_at":"2026-01-05T00:00:00Z","repository":{"full_name":"alice/dotfiles","html_url":"https://github.com/alice/dotfiles"},"subject":{"title":"Alice thread","type":"Issue","url":"https://api.github.com/repos/alice/dotfiles/issues/1"}}]' ;;
  /notifications*:bob) printf '%s\n' '[{"id":"201","unread":true,"reason":"review_requested","updated_at":"2026-01-06T00:00:00Z","repository":{"full_name":"bob/tool","html_url":"https://github.com/bob/tool"},"subject":{"title":"Bob thread","type":"PullRequest","url":"https://api.github.com/repos/bob/tool/pulls/3"}},{"id":"202","unread":true,"reason":"subscribed","updated_at":"2026-01-03T00:00:00Z","repository":{"full_name":"bob/tool","html_url":"https://github.com/bob/tool"},"subject":{"title":"Older Bob thread","type":"Issue","url":"https://api.github.com/repos/bob/tool/issues/2"}}]' ;;
  /search/issues\?q=is%3Aopen+is%3Apr*:alice) printf '%s\n' '{"items":[{"id":1001,"number":9,"title":"Please review","repository_url":"https://api.github.com/repos/alice/dotfiles","html_url":"https://github.com/alice/dotfiles/pull/9","updated_at":"2026-01-04T00:00:00Z","user":{"login":"friend"}}]}' ;;
  /search/issues\?q=is%3Aopen+is%3Aissue*:bob) printf '%s\n' '{"items":[{"id":2001,"number":8,"title":"Fix it","repository_url":"https://api.github.com/repos/bob/tool","html_url":"https://github.com/bob/tool/issues/8","updated_at":"2026-01-02T00:00:00Z","user":{"login":"friend"}}]}' ;;
  /search/issues*) printf '%s\n' '{"items":[]}' ;;
  *) printf '%s\n' '[]' ;;
esac
GH

# Alice and bob have different calendars over the same year, so a merged
# calendar can be told apart from either one.
cat >"$sandbox/bin/curl" <<'CURL'
#!/usr/bin/env bash
case $* in
  *users/alice/contributions*) first=3; second=1 ;;
  *users/bob/contributions*) first=1; second=4 ;;
  *) exit 1 ;;
esac
printf '%s\n' '<h2>calendar</h2>'
for index in $(seq 0 368); do
  day=$(date -u -d "2025-09-07 +$index days" +%F)
  count=0
  [[ $index -ne 0 ]] || count=$first
  [[ $index -ne 1 ]] || count=$second
  level=$count
  printf '<td data-date="%s" data-level="%s"></td>\n' "$day" "$((level > 4 ? 4 : level))"
  if [[ $count -eq 0 ]]; then printf '<tool-tip>No contributions on this day.</tool-tip>\n'
  elif [[ $count -eq 1 ]]; then printf '<tool-tip>1 contribution on this day.</tool-tip>\n'
  else printf '<tool-tip>%s contributions on this day.</tool-tip>\n' "$count"
  fi
done
CURL
chmod +x "$sandbox/bin/gh" "$sandbox/bin/curl"
run() { env -u GH_TOKEN -u GITHUB_TOKEN PATH="$sandbox/bin:$PATH" "$HELPER" --action-scan off "$@"; }
cache() { printf '%s/omarchy-github' "$XDG_CACHE_HOME"; }

# Every login gh knows is fetched with its own token and merged into one
# payload whose rows are tagged with the account they came from.
export XDG_CACHE_HOME="$sandbox/cache-merge"
out=$(OMARCHY_GITHUB_NOW=1000 run --include-contributions false)
assert_jq '.state == "ready" and .login == "" and (.accounts | map(.login)) == ["alice","bob"] and all(.accounts[]; .state == "ready")' "$out" "accounts are discovered from gh"
assert_jq '(.notifications | map([.id, .account])) == [["201","bob"],["101","alice"],["202","bob"]]' "$out" "notifications merge newest first, tagged by account"
assert_jq '(.reviewRequests | map(.account)) == ["alice"] and (.assignedIssues | map(.account)) == ["bob"]' "$out" "review requests and issues are tagged"
assert_jq '(.myPullRequests | map([.id, .account])) == [["bob/tool#3","bob"]] and .myPullRequestsTotal == 3' "$out" "authored pull requests are tagged and their totals add up"
assert_jq '(.repositories | map([.nameWithOwner, .account]) | sort) == [["alice/repo","alice"],["bob/repo","bob"]]' "$out" "repositories are tagged"
assert_jq '.accounts[1].myPullRequestsTotal == 3 and .accounts[0].myPullRequestsTotal == 0' "$out" "each account keeps its own authored pull request total"
assert_jq '.rateLimit.remaining == 4000' "$out" "the shown rate limit is the most constrained account"
assert_jq '(.warnings | length) == 0 and .message == ""' "$out" "healthy accounts raise no warnings"
[[ $(api_calls_for alice) -gt 0 && $(api_calls_for bob) -gt 0 ]] || fail "an account was not fetched with its own token"
if grep -q '^-:api' "$GH_TEST_LOG"; then fail "an API request ran without a pinned token"; fi
if grep -q -- 'auth token -h github.com$' "$GH_TEST_LOG"; then fail "the active account's token was requested for a multi-account scan"; fi
grep -q -- 'auth token -h github.com --user alice' "$GH_TEST_LOG" || fail "alice's token was not requested by login"
grep -q -- 'auth token -h github.com --user bob' "$GH_TEST_LOG" || fail "bob's token was not requested by login"

# Each account has its own private cache, refresh state and lock, and the
# legacy single-account files are left alone.
[[ $(stat -c %a "$(cache)") == 700 && $(stat -c %a "$(cache)/accounts") == 700 ]] || fail "shared cache directories are not private"
for login in alice bob; do
  [[ $(stat -c %a "$(cache)/accounts/$login") == 700 ]] || fail "$login cache directory is not private"
  [[ $(stat -c %a "$(cache)/accounts/$login/dashboard.json") == 600 ]] || fail "$login cache file is not private"
  assert_jq '.schemaVersion == 2 and (.credentialFingerprint | test("^[0-9a-f]{64}$"))' "$(cat "$(cache)/accounts/$login/refresh-state.json")" "$login refresh state"
done
assert_jq '.login == "alice"' "$(cat "$(cache)/accounts/alice/dashboard.json")" "alice cache holds alice's dashboard"
assert_jq '.login == "bob"' "$(cat "$(cache)/accounts/bob/dashboard.json")" "bob cache holds bob's dashboard"
[[ ! -e "$(cache)/dashboard.json" && ! -e "$(cache)/refresh-state.json" ]] || fail "multi-account scan wrote the single-account cache"
if grep -R "ghp_token_for" "$XDG_CACHE_HOME" >/dev/null; then fail "a credential was persisted"; fi

# Freshness is per account: inside the interval nothing touches the API, yet
# the merged view still comes back from the caches.
: >"$GH_TEST_LOG"
cached=$(OMARCHY_GITHUB_NOW=1100 run --include-contributions false --automatic --refresh-interval 300)
assert_jq '.state == "ready" and (.notifications | length) == 3 and (.accounts | length) == 2' "$cached" "automatic restore merges both caches"
[[ $(api_calls_for alice) -eq 0 && $(api_calls_for bob) -eq 0 ]] || fail "fresh caches were refreshed inside the interval"

# One account's rate limit pauses only that account.
GH_RATE_LIMITED=bob OMARCHY_GITHUB_NOW=2000 run --include-contributions false >"$sandbox/limited.json"
limited=$(cat "$sandbox/limited.json")
assert_jq '.state == "ready" and ((.accounts[] | select(.login == "bob")).state) == "rate-limited" and ((.accounts[] | select(.login == "alice")).state) == "ready"' "$limited" "a rate-limited account does not fail the others"
assert_jq '(.warnings | index("bob: GitHub API rate limit reached; refresh is paused.")) != null' "$limited" "the rate-limited account is named in the warnings"
assert_jq '((.accounts[] | select(.login == "bob")).rateLimit) == {remaining:0,resetAt:"1970-01-01T00:43:20Z"}' "$limited" "the account carries its own reset deadline"
assert_jq '(.notifications | map(.id)) == ["201","101","202"]' "$limited" "the paused account keeps showing its cached rows"
assert_jq '.schemaVersion == 2 and .rateLimitUntil == 0' "$(cat "$(cache)/accounts/alice/refresh-state.json")" "alice's refresh state is untouched by bob's limit"
assert_jq '.rateLimitUntil == 2600 and .rateLimitResetKnown == true' "$(cat "$(cache)/accounts/bob/refresh-state.json")" "bob's limit is persisted in bob's state"
: >"$GH_TEST_LOG"
OMARCHY_GITHUB_NOW=2100 run --include-contributions false >"$sandbox/waiting.json"
[[ $(api_calls_for alice) -gt 0 && $(api_calls_for bob) -eq 0 ]] || fail "bob's persisted limit did not hold while alice kept refreshing"
assert_jq '((.accounts[] | select(.login == "bob")).state) == "rate-limited"' "$(cat "$sandbox/waiting.json")" "bob stays paused until his reset"
: >"$GH_TEST_LOG"
resumed=$(OMARCHY_GITHUB_NOW=2601 run --include-contributions false)
assert_jq 'all(.accounts[]; .state == "ready")' "$resumed" "bob resumes after his reset"
[[ $(api_calls_for bob) -gt 0 ]] || fail "bob was not refreshed after his reset"

# When every account is limited the merged view is limited too, and keeps the
# dashboard on screen because every cache is valid.
export XDG_CACHE_HOME="$sandbox/cache-all-limited"
OMARCHY_GITHUB_NOW=1000 run --include-contributions false >/dev/null
all_limited=$(GH_RATE_LIMITED="alice bob" OMARCHY_GITHUB_NOW=2000 run --include-contributions false)
assert_jq '.state == "rate-limited" and .preserveDashboard == true and .message == "GitHub API rate limit reached; refresh is paused." and (.notifications | length) == 3' "$all_limited" "every account limited"

# An account whose token cannot be read is reported without hiding the rest.
export XDG_CACHE_HOME="$sandbox/cache-ghost" GH_TEST_ACCOUNTS="alice ghost"
ghost=$(OMARCHY_GITHUB_NOW=1000 run --include-contributions false)
assert_jq '.state == "ready" and ((.accounts[] | select(.login == "ghost")).state) == "logged-out" and (.notifications | map(.account) | unique) == ["alice"]' "$ghost" "an unreadable token is isolated to its account"
assert_jq '(.warnings | index("ghost: Sign in with gh auth login to load GitHub data.")) != null' "$ghost" "the unreadable account is named in the warnings"
export GH_TEST_ACCOUNTS="alice bob"

# The calendar sums the accounts day by day; each account keeps its own.
export XDG_CACHE_HOME="$sandbox/cache-calendar"
calendar=$(OMARCHY_GITHUB_NOW=1000 run)
assert_jq '.contributions.total == 9 and (.contributions.days | length) == 369' "$calendar" "the merged calendar totals both accounts"
assert_jq '[.contributions.days[0:3][] | .count] == [4,5,0]' "$calendar" "the merged calendar adds the same day across accounts"
assert_jq '[.contributions.days[0:3][] | .level] == [4,4,0]' "$calendar" "merged levels scale to the busiest merged day"
assert_jq '((.accounts[] | select(.login == "alice")).contributions | .total == 4 and .days[0].count == 3)' "$calendar" "alice keeps her own calendar"
assert_jq '((.accounts[] | select(.login == "bob")).contributions | .total == 5 and .days[1].count == 4)' "$calendar" "bob keeps his own calendar"

# Marking read goes out with the token of the account that owns the thread.
: >"$GH_TEST_LOG"
mark_bob=$(run --mark-notification-read 201 --account bob)
assert_jq '.state == "ready" and .notificationId == "201"' "$mark_bob" "marking bob's thread with bob's token"
grep -q '^bob:api --method PATCH /notifications/threads/201$' "$GH_TEST_LOG" || fail "bob's thread was not marked with bob's token"
set +e
mark_wrong=$(run --mark-notification-read 201 --account alice)
mark_wrong_status=$?
set -e
[[ $mark_wrong_status -eq 1 ]] || fail "marking with the wrong account returned status $mark_wrong_status"
assert_jq '.state == "error"' "$mark_wrong" "a thread cannot be marked with another account's token"
: >"$GH_TEST_LOG"
mark_all=$(run --mark-all-read-before 2020-01-03T00:00:00Z --mark-boundary-notification 101 --account alice)
assert_jq '.state == "ready" and .lastReadAt == "2020-01-03T00:00:00Z"' "$mark_all" "bulk marking with alice's token"
[[ $(calls_for alice) -eq 2 ]] || fail "bulk mark did not run entirely as alice"
[[ $(calls_for bob) -eq 0 ]] || fail "bulk mark for alice touched bob's token"

# A mark only invalidates the cache of the account it ran as.
export XDG_CACHE_HOME="$sandbox/cache-invalidate"
OMARCHY_GITHUB_NOW=1000 run --include-contributions false >/dev/null
run --mark-notification-read 101 --account alice >/dev/null
[[ ! -e "$(cache)/accounts/alice/dashboard.json" ]] || fail "marking did not invalidate alice's cache"
[[ -e "$(cache)/accounts/bob/dashboard.json" ]] || fail "marking for alice invalidated bob's cache"

# Anything that is not a multi-account setup keeps today's behaviour: the
# single-credential payload, cache location and token lookup.
export XDG_CACHE_HOME="$sandbox/cache-one" GH_TEST_ACCOUNTS="alice"
: >"$GH_TEST_LOG"
single=$(OMARCHY_GITHUB_NOW=1000 run --include-contributions false)
assert_jq '.state == "ready" and .login == "alice" and (has("accounts") | not) and all(.notifications[]; has("account") | not)' "$single" "one login keeps the single-account payload"
[[ -e "$(cache)/dashboard.json" && ! -e "$(cache)/accounts" ]] || fail "one login moved the cache"
export XDG_CACHE_HOME="$sandbox/cache-env" GH_TEST_ACCOUNTS="alice bob"
: >"$GH_TEST_LOG"
env_token=$(GH_TOKEN=ghp_token_for_bob GITHUB_TOKEN='' PATH="$sandbox/bin:$PATH" OMARCHY_GITHUB_NOW=1000 "$HELPER" --action-scan off --include-contributions false)
assert_jq '.state == "ready" and .login == "bob" and (has("accounts") | not)' "$env_token" "an environment token keeps the single-token payload"
if grep -q 'auth ' "$GH_TEST_LOG"; then fail "an environment token still consulted gh auth"; fi
[[ -e "$(cache)/dashboard.json" && ! -e "$(cache)/accounts" ]] || fail "an environment token moved the cache"
export XDG_CACHE_HOME="$sandbox/cache-no-json"
no_json=$(GH_STATUS_FAILS=true OMARCHY_GITHUB_NOW=1000 run --include-contributions false)
assert_jq '.state == "ready" and .login == "alice" and (has("accounts") | not)' "$no_json" "a gh without account listing keeps the single-account payload"

# --account is validated before it can name a directory or reach gh.
for bad in '../escape' 'a/b' '.hidden' '-dash' ''; do
  if run --account "$bad" >/dev/null 2>&1; then fail "invalid account '$bad' succeeded"; fi
done

echo "account tests passed"
