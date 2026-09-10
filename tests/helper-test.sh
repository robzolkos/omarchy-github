#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER=${HELPER:-"$ROOT/omarchy-github-fetch"}

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_jq() { jq -e "$1" <<<"$2" >/dev/null || fail "$3"; }

bash -n "$HELPER"
"$HELPER" --help >/dev/null
if "$HELPER" --action-scan invalid >/dev/null 2>&1; then fail "invalid scan mode succeeded"; fi
if "$HELPER" --repository-scope invalid >/dev/null 2>&1; then fail "invalid repository scope succeeded"; fi
if "$HELPER" --failed-days 0 >/dev/null 2>&1; then fail "invalid failed window succeeded"; fi
if "$HELPER" --mark-notification-read nope >/dev/null 2>&1; then fail "invalid notification id succeeded"; fi
if "$HELPER" --mark-all-read-before nope >/dev/null 2>&1; then fail "invalid last-read timestamp succeeded"; fi
if "$HELPER" --mark-all-read-before 2026-01-03 >/dev/null 2>&1; then fail "date without time succeeded"; fi
if "$HELPER" --mark-all-read-before 2026-02-30T00:00:00Z --mark-boundary-notification 123 >/dev/null 2>&1; then fail "invalid calendar timestamp succeeded"; fi
if "$HELPER" --mark-all-read-before 9999-01-01T00:00:00Z --mark-boundary-notification 123 >/dev/null 2>&1; then fail "future timestamp succeeded"; fi
near_future=$(jq -nr 'now + 60 | todateiso8601')
if "$HELPER" --mark-all-read-before "$near_future" --mark-boundary-notification 123 >/dev/null 2>&1; then fail "near-future timestamp succeeded"; fi
if "$HELPER" --mark-all-read-before 2020-01-03T00:00:00Z >/dev/null 2>&1; then fail "bulk mark without a boundary notification succeeded"; fi
if "$HELPER" --mark-all-read-before 2020-01-03T00:00:00Z --mark-boundary-notification nope >/dev/null 2>&1; then fail "invalid boundary notification id succeeded"; fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export GH_TEST_LOG="$sandbox/gh-calls"
: >"$GH_TEST_LOG"
ln -s "$(command -v jq)" "$sandbox/jq"
ln -s "$(command -v bash)" "$sandbox/bash"
out=$(PATH="$sandbox" "$HELPER")
assert_jq '.state == "gh-not-installed" and (.reviewRequests|length) == 0' "$out" "missing-gh state"

cat >"$sandbox/gh" <<'GH'
#!/usr/bin/env bash
if [[ $1 == auth ]]; then exit 1; fi
exit 1
GH
chmod +x "$sandbox/gh"
out=$(PATH="$sandbox" "$HELPER")
assert_jq '.state == "logged-out" and (.repositories|length) == 0' "$out" "logged-out state"

cat >"$sandbox/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_TEST_LOG"
if [[ ${CURL_FAIL_CONTRIBUTIONS:-} == true ]]; then
  echo "profile contribution request failed" >&2
  exit 1
fi
if [[ ${CURL_INVALID_CONTRIBUTIONS:-} == true ]]; then
  printf '%s\n' '<html>not a contribution calendar</html>'
  exit 0
fi
printf '%s\n' '<h2>15 contributions in the last year</h2>'
for index in $(seq 0 368); do
  day=$(date -u -d "2025-09-07 +$index days" +%F)
  if [[ $index -eq 0 ]]; then count=1; level=1
  elif [[ $index -eq 1 ]]; then count=14; level=4
  else count=0; level=0
  fi
  if [[ $index -eq 0 ]]; then printf '<td data-level="%s" data-date="%s"></td>\n' "$level" "$day"
  else printf '<td data-date="%s" data-level="%s"></td>\n' "$day" "$level"
  fi
  if [[ $count -eq 0 ]]; then printf '<tool-tip>No contributions on this day.</tool-tip>\n'
  elif [[ $count -eq 1 ]]; then printf '<tool-tip>1 contribution on this day.</tool-tip>\n'
  else printf '<tool-tip>%s contributions on this day.</tool-tip>\n' "$count"
  fi
done
CURL
chmod +x "$sandbox/curl"

cat >"$sandbox/gh" <<'GH'
#!/usr/bin/env bash
if [[ $1 == auth ]]; then exit 0; fi
if [[ $1 == api && $2 == --method && $3 == PATCH ]]; then
  printf '%s\n' "$*" >>"$GH_TEST_LOG"
  id=${4##*/}
  [[ $id == 123 || $id == 124 || $id == 125 ]] || exit 9
  if [[ ${GH_FAIL_PATCH_ID:-} == "$id" ]]; then echo "boundary patch rejected ghp_abcdefghijklmnopqrstuvwxyz123456" >&2; exit 8; fi
  printf '%s\n' '{}'; exit 0
fi
if [[ $1 == api && $2 == --method && $3 == PUT ]]; then
  printf '%s\n' "$*" >>"$GH_TEST_LOG"
  [[ $4 == /notifications ]] || exit 9
  [[ $5 == -f && $6 == last_read_at=2020-01-02T23:59:59Z ]] || { echo "unexpected last_read_at: ${6-}" >&2; exit 9; }
  printf '%s\n' '{}'; exit 0
fi
if [[ $1 == api && $2 == graphql ]]; then
  printf '%s\n' "$*" >>"$GH_TEST_LOG"
  if [[ $* == *contributionsCollection* ]]; then
    if [[ ${GH_CONTRIBUTION_RATE:-} == true ]]; then
      printf '%s\n' '{"data":{"viewer":{"contributionsCollection":{"contributionCalendar":{"totalContributions":1,"weeks":[{"contributionDays":[{"date":"2025-09-07","contributionCount":1,"contributionLevel":"FIRST_QUARTILE"}]}]}}},"rateLimit":{"remaining":0,"resetAt":"2026-01-01T01:00:00Z","cost":1}}}'
      exit 0
    fi
    if [[ ${GH_INVALID_CONTRIBUTIONS:-} == true ]]; then
      printf '%s\n' '{"data":{"viewer":{"contributionsCollection":{"contributionCalendar":{"totalContributions":null}}}}}'
      exit 0
    fi
    # These counts deliberately cross the helper's former fixed boundaries.
    # GitHub's enum remains authoritative when its dynamic quartiles differ.
    cat <<'JSON'
{"data":{"viewer":{"contributionsCollection":{"contributionCalendar":{"totalContributions":14,"weeks":[{"contributionDays":[{"date":"2025-09-07","contributionCount":0,"contributionLevel":"NONE"},{"date":"2025-09-08","contributionCount":1,"contributionLevel":"FIRST_QUARTILE"},{"date":"2025-09-09","contributionCount":2,"contributionLevel":"SECOND_QUARTILE"},{"date":"2025-09-10","contributionCount":4,"contributionLevel":"THIRD_QUARTILE"},{"date":"2025-09-11","contributionCount":7,"contributionLevel":"FOURTH_QUARTILE"},{"date":"2025-09-12","contributionCount":0,"contributionLevel":"NONE"},{"date":"2025-09-13","contributionCount":0,"contributionLevel":"NONE"}]},{"contributionDays":[{"date":"2025-09-14","contributionCount":0,"contributionLevel":"NONE"},{"date":"2025-09-15","contributionCount":0,"contributionLevel":"NONE"},{"date":"2025-09-16","contributionCount":0,"contributionLevel":"NONE"},{"date":"2025-09-17","contributionCount":0,"contributionLevel":"NONE"},{"date":"2025-09-18","contributionCount":0,"contributionLevel":"NONE"},{"date":"2025-09-19","contributionCount":0,"contributionLevel":"NONE"},{"date":"2025-09-20","contributionCount":0,"contributionLevel":"NONE"}]}]}}}}}
JSON
    exit 0
  fi
  if [[ $* == *author:@me* ]]; then
    # The second node carries no rollup, which must land as NONE rather than
    # being conflated with a pending run.
    cat <<'JSON'
{"data":{"search":{"issueCount":2,"nodes":[{"number":7,"title":"Ship it","url":"https://github.com/octocat/hello/pull/7","updatedAt":"2026-01-05T00:00:00Z","isDraft":false,"repository":{"nameWithOwner":"octocat/hello"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},{"number":9,"title":"No CI here","url":"https://github.com/octocat/quiet/pull/9","updatedAt":"2026-01-04T00:00:00Z","isDraft":true,"repository":{"nameWithOwner":"octocat/quiet"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}]}}}
JSON
    exit 0
  fi
  if [[ $* == *'ownerAffiliations:[OWNER,ORGANIZATION_MEMBER]'* ]]; then
    cat <<'JSON'
{"data":{"viewer":{"login":"octocat","repositories":{"nodes":[{"name":"hello","nameWithOwner":"octocat/hello","url":"https://github.com/octocat/hello","isArchived":false,"isFork":false,"stargazerCount":42,"updatedAt":"2026-01-01T00:00:00Z","issues":{"totalCount":3},"pullRequests":{"totalCount":2}},{"name":"work","nameWithOwner":"acme/work","url":"https://github.com/acme/work","isArchived":false,"isFork":false,"stargazerCount":7,"updatedAt":"2026-01-06T00:00:00Z","issues":{"totalCount":4},"pullRequests":{"totalCount":5}},{"name":"old","nameWithOwner":"octocat/old","url":"https://github.com/octocat/old","isArchived":true,"isFork":false,"stargazerCount":1,"updatedAt":"2020-01-01T00:00:00Z","issues":{"totalCount":0},"pullRequests":{"totalCount":0}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"remaining":4998,"resetAt":"2026-01-01T01:00:00Z","cost":2}}}
JSON
    exit 0
  fi
  cat <<'JSON'
{"data":{"viewer":{"login":"octocat","repositories":{"nodes":[{"name":"hello","nameWithOwner":"octocat/hello","url":"https://github.com/octocat/hello","isArchived":false,"isFork":false,"stargazerCount":42,"updatedAt":"2026-01-01T00:00:00Z","issues":{"totalCount":3},"pullRequests":{"totalCount":2}},{"name":"old","nameWithOwner":"octocat/old","url":"https://github.com/octocat/old","isArchived":true,"isFork":false,"stargazerCount":1,"updatedAt":"2020-01-01T00:00:00Z","issues":{"totalCount":0},"pullRequests":{"totalCount":0}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"remaining":4999,"resetAt":"2026-01-01T01:00:00Z","cost":1}}}
JSON
  exit 0
fi
endpoint=${*: -1}
printf '%s\n' "$*" >>"$GH_TEST_LOG"
if [[ $endpoint == /notifications* ]]; then
  cat <<'JSON'
[{"id":"123","unread":true,"reason":"mention","updated_at":"2026-01-03T00:00:00Z","repository":{"full_name":"octocat/hello","html_url":"https://github.com/octocat/hello"},"subject":{"title":"Review this","type":"PullRequest","url":"https://api.github.com/repos/octocat/hello/pulls/7","latest_comment_url":null}},{"id":"124","unread":true,"reason":"subscribed","updated_at":"2026-01-02T00:00:00Z","repository":{"full_name":"octocat/hello","html_url":"https://github.com/octocat/hello"},"subject":{"title":"Unknown subject","type":"RepositoryVulnerabilityAlert","url":"https://api.github.com/repos/octocat/hello/private-vulnerability-reporting/1","latest_comment_url":"https://api.github.com/repos/octocat/hello/comments/1"}}]
JSON
  exit 0
fi
if [[ $endpoint == /search/issues\?q=is%3Aopen+is%3Apr* ]]; then
  cat <<'JSON'
{"items":[{"id":71,"number":7,"title":"Please review","repository_url":"https://api.github.com/repos/octocat/hello","html_url":"https://github.com/octocat/hello/pull/7","updated_at":"2026-01-02T00:00:00Z","user":{"login":"friend"}}]}
JSON
  exit 0
fi
if [[ $endpoint == /search/issues\?q=is%3Aopen+is%3Aissue* ]]; then
  cat <<'JSON'
{"items":[{"id":81,"number":8,"title":"Fix it","repository_url":"https://api.github.com/repos/octocat/hello","html_url":"https://github.com/octocat/hello/issues/8","updated_at":"2026-01-02T00:00:00Z","user":{"login":"friend"}}]}
JSON
  exit 0
fi
if [[ $endpoint == /repos/octocat/hello/actions/runs* ]]; then
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ $endpoint == *status=queued* ]]; then
    # Simulate a paginated response where the active run is beyond the first
    # 100 records. A non-paginated or unfiltered implementation misses id 10.
    jq -n --arg now "$now" '{workflow_runs:[range(100)|{id:(1000+.),name:"Old",status:"completed",conclusion:"success",created_at:$now,updated_at:$now}]}'
    cat <<JSON
{"workflow_runs":[{"id":10,"name":"CI","display_title":"Build","status":"queued","conclusion":null,"head_branch":"main","html_url":"https://github.com/octocat/hello/actions/runs/10","created_at":"$now","updated_at":"$now"}]}
JSON
  elif [[ $endpoint == *status=completed* ]]; then
    jq -n --arg now "$now" '{workflow_runs:[range(100)|{id:(2000+.),name:"Passed",status:"completed",conclusion:"success",created_at:$now,updated_at:$now}]}'
    cat <<JSON
{"workflow_runs":[{"id":11,"name":"Test","status":"completed","conclusion":"failure","head_branch":"main","html_url":"https://github.com/octocat/hello/actions/runs/11","created_at":"$now","updated_at":"$now"}]}
JSON
  else
    printf '%s\n' '{"workflow_runs":[]}'
  fi
  exit 0
fi
exit 1
GH
chmod +x "$sandbox/gh"
out=$(PATH="$sandbox:$PATH" "$HELPER" --action-scan all --failed-days 7 --failed-limit 5)
assert_jq '.state == "ready" and .login == "octocat"' "$out" "ready state"
assert_jq '.repositories|length == 1 and .[0].issues == 3 and .[0].prs == 2 and .[0].stars == 42 and .[0].activeActions == 1' "$out" "repository metrics"
assert_jq '.notifications|length == 2 and .[0].url == "https://github.com/octocat/hello/pull/7" and .[1].url == "https://github.com/octocat/hello"' "$out" "type-aware notification conversion and fallback"
assert_jq '.reviewRequests|length == 1 and .[0].repository == "octocat/hello"' "$out" "review requests"
assert_jq '(.assignedIssues|length == 1) and (.assignedIssues[0].url|endswith("/issues/8"))' "$out" "assigned issues"
assert_jq '(.actions|length == 1) and (.failedActions|length == 1)' "$out" "active and failed actions separated"
assert_jq '.repositoryScope == "owned"' "$out" "default repository scope reported"
assert_jq '.rateLimit.remaining == 4999 and (.warnings|length) == 0' "$out" "rate limit and warnings"
assert_jq '(.contributions.total == 15) and (.contributions.days|length == 369)' "$out" "contribution calendar matches the profile graph"
assert_jq '[.contributions.days[0:2][].level] == [1,4]' "$out" "profile contribution levels map to the five panel levels"
assert_jq '(.contributions.days[0].count == 1 and .contributions.days[0].level == 1) and (.contributions.days[1].count == 14 and .contributions.days[1].level == 4)' "$out" "profile contribution counts and levels stay paired by date"
grep -q 'https://github.com/users/octocat/contributions' "$GH_TEST_LOG" || fail "contribution calendar did not request the profile graph"
if grep -q 'contributionsCollection.*contributionLevel' "$GH_TEST_LOG"; then fail "contribution calendar used GraphQL despite a valid profile response"; fi
invalid_contributions=$(CURL_INVALID_CONTRIBUTIONS=true GH_INVALID_CONTRIBUTIONS=true PATH="$sandbox:$PATH" "$HELPER" --action-scan off)
assert_jq '(.contributions.total == 0) and (.contributions.days|length == 0) and (.warnings|index("contributions: invalid API response") != null)' "$invalid_contributions" "invalid profile and API contribution payloads fall back with a warning"
contribution_rate=$(CURL_FAIL_CONTRIBUTIONS=true GH_CONTRIBUTION_RATE=true PATH="$sandbox:$PATH" "$HELPER" --action-scan off)
assert_jq '.rateLimit.remaining == 0 and .rateLimit.cost == 1 and .state == "rate-limited"' "$contribution_rate" "contribution API fallback updates the displayed rate limit"
grep -q 'contributionsCollection.*rateLimit.*remaining' "$GH_TEST_LOG" || fail "contribution fallback did not request the final rate limit"
assert_jq '(.myPullRequests|length == 2) and (.myPullRequests[0].id == "octocat/hello#7") and (.myPullRequests[0].checks == "FAILURE")' "$out" "authored pull requests with check rollup"
assert_jq '(.myPullRequests[1].checks == "NONE") and (.myPullRequests[1].draft == true)' "$out" "missing rollup falls back to NONE"
assert_jq '.myPullRequestsTotal == 2' "$out" "authored pull request total reported"
grep -q 'author:@me.*sort:updated-desc' "$GH_TEST_LOG" || fail "authored pull request search was not server sorted"
grep -q 'author:@me.*archived:false' "$GH_TEST_LOG" || fail "authored pull request search was not archive filtered"
grep -q -- '--paginate.*status=queued' "$GH_TEST_LOG" || fail "queued Actions request was not paginated"
grep -q 'status=completed.*created=%3E%3D' "$GH_TEST_LOG" || fail "completed Actions request was not date bounded"
grep -q 'review-requested%3A%40me+draft%3Afalse+archived%3Afalse' "$GH_TEST_LOG" || fail "review request search was not draft and archive filtered"
grep -q 'assignee%3A%40me+archived%3Afalse' "$GH_TEST_LOG" || fail "assigned issue search was not archive filtered"
: >"$GH_TEST_LOG"
out_archived_reviews=$(PATH="$sandbox:$PATH" "$HELPER" --action-scan off --include-archived-reviews true)
assert_jq '(.reviewRequests|length == 1) and (.assignedIssues|length == 1)' "$out_archived_reviews" "searches still return with archived included"
if grep -q 'archived%3Afalse' "$GH_TEST_LOG"; then fail "archived filter applied despite --include-archived-reviews true"; fi
# The draft exclusion has its own setting, so it must survive the archived one.
grep -q 'draft%3Afalse' "$GH_TEST_LOG" || fail "draft exclusion dropped when archived repositories are included"
: >"$GH_TEST_LOG"
out_drafts=$(PATH="$sandbox:$PATH" "$HELPER" --action-scan off --include-draft-reviews true)
assert_jq '.reviewRequests|length == 1' "$out_drafts" "review requests still return with drafts included"
if grep -q 'draft%3Afalse' "$GH_TEST_LOG"; then fail "draft filter applied despite --include-draft-reviews true"; fi
grep -q 'archived%3Afalse' "$GH_TEST_LOG" || fail "archived filter dropped when drafts are included"
# The repository-list archive setting independently controls authored PRs.
: >"$GH_TEST_LOG"
out_archived=$(PATH="$sandbox:$PATH" "$HELPER" --action-scan off --include-archived true)
assert_jq '.myPullRequests|length == 2' "$out_archived" "authored pull requests survive the archived setting"
grep -q 'author:@me' "$GH_TEST_LOG" || fail "authored pull request search did not run"
if grep -q 'archived:false' "$GH_TEST_LOG"; then fail "archived filter applied despite --include-archived true"; fi
# Each scope run truncates the log first, so the greps below read only the run
# they belong to rather than an earlier one that used the other affiliation.
: >"$GH_TEST_LOG"
out_owned=$(PATH="$sandbox:$PATH" "$HELPER" --action-scan off)
assert_jq '.repositoryScope == "owned" and (.repositories|length) == 1 and ([.repositories[].nameWithOwner]|index("acme/work")|not)' "$out_owned" "owned scope excludes organization repositories"
grep -q 'ownerAffiliations:OWNER,' "$GH_TEST_LOG" || fail "default scope did not query owned repositories"
: >"$GH_TEST_LOG"
out_scoped=$(PATH="$sandbox:$PATH" "$HELPER" --action-scan off --repository-scope organizations)
assert_jq '.repositoryScope == "organizations" and (.repositories|length) == 2 and ([.repositories[].nameWithOwner]|index("acme/work") != null)' "$out_scoped" "organization scope includes organization repositories"
grep -q 'ownerAffiliations:\[OWNER,ORGANIZATION_MEMBER\],' "$GH_TEST_LOG" || fail "organization scope did not reach the query"
if grep -q 'ownerAffiliations:OWNER,' "$GH_TEST_LOG"; then fail "owned affiliation used despite the organization scope"; fi

: >"$GH_TEST_LOG"
mark=$(PATH="$sandbox:$PATH" "$HELPER" --mark-notification-read 123)
assert_jq '.state == "ready" and .notificationId == "123"' "$mark" "mark notification read"
: >"$GH_TEST_LOG"
mark_all=$(PATH="$sandbox:$PATH" "$HELPER" --mark-all-read-before 2020-01-03T00:00:00Z --mark-boundary-notification 123 --mark-boundary-notification 124)
assert_jq '.state == "ready" and .lastReadAt == "2020-01-03T00:00:00Z"' "$mark_all" "mark all notifications read"
mapfile -t mark_calls <"$GH_TEST_LOG"
[[ ${#mark_calls[@]} -eq 3 ]] || fail "bulk mark made an unexpected number of API calls"
[[ ${mark_calls[0]} == 'api --method PUT /notifications -f last_read_at=2020-01-02T23:59:59Z' ]] || fail "bulk mark did not stop before the boundary second"
[[ ${mark_calls[1]} == 'api --method PATCH /notifications/threads/123' && ${mark_calls[2]} == 'api --method PATCH /notifications/threads/124' ]] || fail "bulk mark did not patch exactly the confirmed boundary notifications"
: >"$GH_TEST_LOG"
set +e
mark_partial=$(GH_FAIL_PATCH_ID=124 PATH="$sandbox:$PATH" "$HELPER" --mark-all-read-before 2020-01-03T00:00:00Z --mark-boundary-notification 123 --mark-boundary-notification 124 --mark-boundary-notification 125)
mark_partial_status=$?
set -e
[[ $mark_partial_status -eq 1 ]] || fail "partial boundary failure returned status $mark_partial_status"
assert_jq '.state == "error" and .notificationId == "124" and (.message|test("boundary patch rejected")) and (.message|contains("ghp_")|not) and (.message|contains("[REDACTED]"))' "$mark_partial" "partial boundary failure reports the failing notification without exposing credentials"
mapfile -t partial_calls <"$GH_TEST_LOG"
[[ ${#partial_calls[@]} -eq 3 && ${partial_calls[0]} == 'api --method PUT /notifications -f last_read_at=2020-01-02T23:59:59Z' && ${partial_calls[1]} == 'api --method PATCH /notifications/threads/123' && ${partial_calls[2]} == 'api --method PATCH /notifications/threads/124' ]] || fail "partial boundary failure did not stop at the failing notification"
# A rejected request must surface as an error payload rather than an empty
# response, which is what a missing notifications scope looks like in practice.
set +e
mark_all_failed=$(PATH="$sandbox:$PATH" "$HELPER" --mark-all-read-before 2020-01-01T00:00:00Z --mark-boundary-notification 123)
mark_all_failed_status=$?
set -e
[[ $mark_all_failed_status -eq 1 ]] || fail "failed bulk mark returned status $mark_all_failed_status"
assert_jq '.state == "error" and .lastReadAt == "2020-01-01T00:00:00Z"' "$mark_all_failed" "failed mark all reports an error"

mkdir "$sandbox/failbin"
cat >"$sandbox/failbin/mktemp" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$sandbox/failbin/mktemp"
set +e
mark_setup_failed=$(PATH="$sandbox/failbin:$sandbox:$PATH" "$HELPER" --mark-notification-read 123)
mark_setup_status=$?
bulk_setup_failed=$(PATH="$sandbox/failbin:$sandbox:$PATH" "$HELPER" --mark-all-read-before 2020-01-03T00:00:00Z --mark-boundary-notification 123)
bulk_setup_status=$?
fetch_setup_failed=$(PATH="$sandbox/failbin:$sandbox:$PATH" "$HELPER")
fetch_setup_status=$?
set -e
[[ $mark_setup_status -eq 1 && $bulk_setup_status -eq 1 && $fetch_setup_status -eq 1 ]] || fail "temporary-storage failures returned an unexpected status"
assert_jq '.state == "error" and .notificationId == "123"' "$mark_setup_failed" "single mark setup failure reports an error"
assert_jq '.state == "error" and .lastReadAt == "2020-01-03T00:00:00Z"' "$bulk_setup_failed" "bulk mark setup failure reports an error"
assert_jq '.state == "error"' "$fetch_setup_failed" "refresh setup failure reports an error"

# The Actions scan runs in xargs subshells, which only see exported functions.
# An unexported helper there degrades every warning to the generic fallback
# instead of the API's own explanation.
cat >"$sandbox/gh" <<'GH'
#!/usr/bin/env bash
if [[ $1 == auth ]]; then exit 0; fi
if [[ $1 == api && $2 == graphql ]]; then
  printf '%s\n' "$*" >>"$GH_TEST_LOG"
  cat <<'JSON'
{"data":{"viewer":{"login":"octocat","repositories":{"nodes":[{"name":"hello","nameWithOwner":"octocat/hello","url":"https://github.com/octocat/hello","isArchived":false,"isFork":false,"stargazerCount":1,"updatedAt":"2026-01-01T00:00:00Z","issues":{"totalCount":0},"pullRequests":{"totalCount":0}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"remaining":10,"resetAt":"2026-01-01T01:00:00Z","cost":1}}}
JSON
  exit 0
fi
endpoint=${*: -1}
if [[ $endpoint == /repos/octocat/hello/actions/runs* ]]; then
  echo "HTTP 403: Resource not accessible by integration" >&2
  exit 1
fi
printf '%s\n' '[]'
GH
chmod +x "$sandbox/gh"
scoped=$(PATH="$sandbox:$PATH" "$HELPER" --action-scan all)
assert_jq '(.warnings|length) > 0 and (.warnings[0]|test("403"))' "$scoped" "Actions warnings keep the API error text"

: >"$GH_TEST_LOG"
out_no_contrib=$(PATH="$sandbox:$PATH" "$HELPER" --include-contributions false)
if grep -q 'contributionsCollection\|/contributions' "$GH_TEST_LOG"; then fail "contribution query ran despite --include-contributions false"; fi
assert_jq '(.contributions.total == 0) and (.contributions.days|length == 0)' "$out_no_contrib" "contribution calendar is empty when disabled"

echo "helper tests passed"
