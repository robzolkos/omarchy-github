#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/omarchy-gitlab-fetch"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_jq() { jq -e "$1" <<<"$2" >/dev/null || fail "$3"; }

bash -n "$HELPER"
"$HELPER" --help >/dev/null
if "$HELPER" --scan invalid >/dev/null 2>&1; then fail "invalid scan mode succeeded"; fi
if "$HELPER" --repository-scope invalid >/dev/null 2>&1; then fail "invalid repository scope succeeded"; fi
if "$HELPER" --failed-days 0 >/dev/null 2>&1; then fail "invalid failed window succeeded"; fi
if "$HELPER" --mark-notification-read nope >/dev/null 2>&1; then fail "invalid notification id succeeded"; fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export GLAB_TEST_LOG="$sandbox/glab-calls"
: >"$GLAB_TEST_LOG"
ln -s "$(command -v jq)" "$sandbox/jq"
ln -s "$(command -v bash)" "$sandbox/bash"
ln -s "$(command -v date)" "$sandbox/date"
ln -s "$(command -v sort)" "$sandbox/sort"
ln -s "$(command -v xargs)" "$sandbox/xargs"
ln -s "$(command -v sed)" "$sandbox/sed"
ln -s "$(command -v tr)" "$sandbox/tr"
ln -s "$(command -v cut)" "$sandbox/cut"
ln -s "$(command -v grep)" "$sandbox/grep"
ln -s "$(command -v mktemp)" "$sandbox/mktemp"
out=$(PATH="$sandbox" "$HELPER")
assert_jq '.state == "glab-not-installed" and (.reviewRequests|length) == 0' "$out" "missing-glab state"

cat >"$sandbox/glab" <<'GLAB'
#!/usr/bin/env bash
if [[ $1 == config ]]; then exit 0; fi
if [[ $1 == auth ]]; then exit 1; fi
exit 1
GLAB
chmod +x "$sandbox/glab"
out=$(PATH="$sandbox" "$HELPER")
assert_jq '.state == "logged-out" and (.repositories|length) == 0' "$out" "logged-out state"

cat >"$sandbox/glab" <<'GLAB'
#!/usr/bin/env bash
if [[ $1 == config ]]; then
  case "${4:-}" in
    host) echo "example.gitlab.test" ;;
    api_protocol) echo "https" ;;
  esac
  exit 0
fi
if [[ $1 == auth ]]; then exit 0; fi
if [[ $1 == api && $2 == --method && $3 == POST ]]; then
  printf '%s\n' "$*" >>"$GLAB_TEST_LOG"
  id=$(printf '%s' "$4" | grep -oE '^todos/[0-9]+' | cut -d/ -f2)
  [[ $id == 123 || $id == 124 || $id == 125 ]] || exit 9
  if [[ ${GLAB_FAIL_MARK_ID:-} == "$id" ]]; then echo "mark rejected glpat-abcdefghijklmnopqrst" >&2; exit 8; fi
  printf '%s\n' '{}'; exit 0
fi
if [[ $1 == api && $2 == graphql ]]; then
  printf '%s\n' "$*" >>"$GLAB_TEST_LOG"
  if [[ $* == *authoredMergeRequests* ]]; then
    # The second node carries no head pipeline, which must land as NONE
    # rather than being conflated with a pending run.
    cat <<'JSON'
{"data":{"currentUser":{"username":"octocat","authoredMergeRequests":{"count":2,"nodes":[{"iid":"7","title":"Ship it","webUrl":"https://example.gitlab.test/octocat/hello/-/merge_requests/7","updatedAt":"2026-01-05T00:00:00Z","draft":false,"project":{"fullPath":"octocat/hello"},"headPipeline":{"status":"FAILED"}},{"iid":"9","title":"No CI here","webUrl":"https://example.gitlab.test/octocat/quiet/-/merge_requests/9","updatedAt":"2026-01-04T00:00:00Z","draft":true,"project":{"fullPath":"octocat/quiet"},"headPipeline":null}]}}}}
JSON
    exit 0
  fi
  if [[ $* == *'projects(membership: true'* ]]; then
    cat <<'JSON'
{"data":{"projects":{"count":2,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"gid://gitlab/Project/1","fullPath":"octocat/hello","webUrl":"https://example.gitlab.test/octocat/hello","archived":false,"isForked":false,"starCount":42,"forksCount":0,"lastActivityAt":"2026-01-01T00:00:00Z","issues":{"count":3},"mergeRequests":{"count":2}},{"id":"gid://gitlab/Project/2","fullPath":"acme/work","webUrl":"https://example.gitlab.test/acme/work","archived":false,"isForked":false,"starCount":7,"forksCount":0,"lastActivityAt":"2026-01-06T00:00:00Z","issues":{"count":4},"mergeRequests":{"count":5}}]}}}
JSON
    exit 0
  fi
  if [[ $* == *'projects(personal: true'* ]]; then
    cat <<'JSON'
{"data":{"projects":{"count":2,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"gid://gitlab/Project/1","fullPath":"octocat/hello","webUrl":"https://example.gitlab.test/octocat/hello","archived":false,"isForked":false,"starCount":42,"forksCount":0,"lastActivityAt":"2026-01-01T00:00:00Z","issues":{"count":3},"mergeRequests":{"count":2}},{"id":"gid://gitlab/Project/3","fullPath":"octocat/old","webUrl":"https://example.gitlab.test/octocat/old","archived":true,"isForked":false,"starCount":1,"forksCount":0,"lastActivityAt":"2020-01-01T00:00:00Z","issues":{"count":0},"mergeRequests":{"count":0}}]}}}
JSON
    exit 0
  fi
  exit 9
fi
endpoint=${*: -1}
printf '%s\n' "$*" >>"$GLAB_TEST_LOG"
if [[ $endpoint == todos\?state=pending* ]]; then
  cat <<'JSON'
[{"id":123,"action_name":"mentioned","updated_at":"2026-01-03T00:00:00Z","project":{"path_with_namespace":"octocat/hello"},"target_type":"MergeRequest","target":{"title":"Review this"},"target_url":"https://example.gitlab.test/octocat/hello/-/merge_requests/7"},{"id":124,"action_name":"assigned","updated_at":"2026-01-02T00:00:00Z","project":{"path_with_namespace":"octocat/hello"},"target_type":"Issue","target":{"title":"Unknown subject"},"target_url":"https://example.gitlab.test/octocat/hello/-/issues/1"}]
JSON
  exit 0
fi
if [[ $endpoint == merge_requests\?scope=all* ]]; then
  cat <<'JSON'
[{"id":71,"iid":7,"title":"Please review","references":{"full":"octocat/hello!7"},"web_url":"https://example.gitlab.test/octocat/hello/-/merge_requests/7","updated_at":"2026-01-02T00:00:00Z","author":{"username":"friend"},"draft":false}]
JSON
  exit 0
fi
if [[ $endpoint == issues\?scope=all* ]]; then
  cat <<'JSON'
[{"id":81,"iid":8,"title":"Fix it","references":{"full":"octocat/hello#8"},"web_url":"https://example.gitlab.test/octocat/hello/-/issues/8","updated_at":"2026-01-02T00:00:00Z","author":{"username":"friend"}}]
JSON
  exit 0
fi
if [[ $endpoint == projects/1/pipelines\?status=running* ]]; then
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\n' "[{\"id\":10,\"status\":\"running\",\"source\":\"push\",\"ref\":\"main\",\"web_url\":\"https://example.gitlab.test/octocat/hello/-/pipelines/10\",\"created_at\":\"$now\",\"updated_at\":\"$now\"}]"
  exit 0
fi
if [[ $endpoint == projects/1/pipelines\?status=failed* ]]; then
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\n' "[{\"id\":11,\"status\":\"failed\",\"source\":\"push\",\"ref\":\"main\",\"web_url\":\"https://example.gitlab.test/octocat/hello/-/pipelines/11\",\"created_at\":\"$now\",\"updated_at\":\"$now\"}]"
  exit 0
fi
if [[ $endpoint == projects/*/pipelines* ]]; then
  printf '%s\n' '[]'
  exit 0
fi
exit 1
GLAB
chmod +x "$sandbox/glab"

out=$(PATH="$sandbox:$PATH" "$HELPER" --scan all --failed-days 7 --failed-limit 5)
assert_jq '.state == "ready" and .login == "octocat" and .provider == "gitlab" and .host == "https://example.gitlab.test"' "$out" "ready state"
assert_jq '.repositories|length == 1 and .[0].issues == 3 and .[0].prs == 2 and .[0].stars == 42 and .[0].activeRuns == 1' "$out" "repository metrics"
assert_jq '.notifications|length == 2 and .[0].url == "https://example.gitlab.test/octocat/hello/-/merge_requests/7" and .[1].url == "https://example.gitlab.test/octocat/hello/-/issues/1"' "$out" "todo mapping passes through the ready-made web URL"
assert_jq '.reviewRequests|length == 1 and .[0].repository == "octocat/hello" and .[0].number == 7' "$out" "review requests parse the project path from references.full"
assert_jq '(.assignedIssues|length == 1) and (.assignedIssues[0].repository == "octocat/hello") and (.assignedIssues[0].url|endswith("/issues/8"))' "$out" "assigned issues"
assert_jq '(.runs|length == 1) and (.failedRuns|length == 1)' "$out" "active and failed pipelines separated"
assert_jq '.repositoryScope == "owned"' "$out" "default repository scope reported"
assert_jq '(.warnings|length) == 0 and .rateLimit == null' "$out" "no warnings and no rate limit endpoint on self-hosted"
assert_jq '(.authored|length == 2) and (.authored[0].id == "octocat/hello!7") and (.authored[0].checks == "FAILURE")' "$out" "authored merge requests with head pipeline status"
assert_jq '(.authored[1].checks == "NONE") and (.authored[1].draft == true)' "$out" "missing head pipeline falls back to NONE"
assert_jq '.authoredTotal == 2' "$out" "authored merge request total reported"
grep -q 'projects(personal: true' "$GLAB_TEST_LOG" || fail "default repository scope did not query personal projects"

: >"$GLAB_TEST_LOG"
out_archived_reviews=$(PATH="$sandbox:$PATH" "$HELPER" --scan off --include-archived-reviews true)
assert_jq '(.reviewRequests|length == 1) and (.assignedIssues|length == 1)' "$out_archived_reviews" "searches still return with archived projects included"
if grep -q 'non_archived=true' "$GLAB_TEST_LOG"; then fail "archived filter applied despite --include-archived-reviews true"; fi
grep -q 'draft=no' "$GLAB_TEST_LOG" || fail "draft exclusion dropped when archived projects are included"

: >"$GLAB_TEST_LOG"
out_drafts=$(PATH="$sandbox:$PATH" "$HELPER" --scan off --include-draft-reviews true)
assert_jq '.reviewRequests|length == 1' "$out_drafts" "review requests still return with drafts included"
if grep -q 'draft=no' "$GLAB_TEST_LOG"; then fail "draft filter applied despite --include-draft-reviews true"; fi
grep -q 'non_archived=true' "$GLAB_TEST_LOG" || fail "archived filter dropped when drafts are included"

: >"$GLAB_TEST_LOG"
out_wider=$(PATH="$sandbox:$PATH" "$HELPER" --scan off --repository-scope wider)
assert_jq '.repositoryScope == "wider" and (.repositories|length) == 2 and ([.repositories[].nameWithOwner]|index("acme/work") != null)' "$out_wider" "wider scope includes every membership project"
grep -q 'projects(membership: true' "$GLAB_TEST_LOG" || fail "wider scope did not reach the query"
if grep -q 'projects(personal: true' "$GLAB_TEST_LOG"; then fail "personal scope used despite the wider scope"; fi

: >"$GLAB_TEST_LOG"
mark=$(PATH="$sandbox:$PATH" "$HELPER" --mark-notification-read 123)
assert_jq '.state == "ready"' "$mark" "mark a single notification read"
mapfile -t mark_calls <"$GLAB_TEST_LOG"
[[ ${#mark_calls[@]} -eq 1 && ${mark_calls[0]} == 'api --method POST todos/123/mark_as_done' ]] || fail "single mark issued an unexpected call"

: >"$GLAB_TEST_LOG"
mark_all=$(PATH="$sandbox:$PATH" "$HELPER" --mark-notification-read 123 --mark-notification-read 124)
assert_jq '.state == "ready"' "$mark_all" "mark several notifications read in one run"
mapfile -t mark_all_calls <"$GLAB_TEST_LOG"
[[ ${#mark_all_calls[@]} -eq 2 ]] || fail "bulk mark made an unexpected number of API calls"

: >"$GLAB_TEST_LOG"
set +e
mark_partial=$(GLAB_FAIL_MARK_ID=124 PATH="$sandbox:$PATH" "$HELPER" --mark-notification-read 123 --mark-notification-read 124 --mark-notification-read 125)
mark_partial_status=$?
set -e
[[ $mark_partial_status -eq 1 ]] || fail "partial mark failure returned status $mark_partial_status"
assert_jq '.state == "error" and .notificationId == "124" and (.message|test("mark rejected")) and (.message|contains("glpat-")|not) and (.message|contains("[REDACTED]"))' "$mark_partial" "partial mark failure reports the failing id without exposing the token"
mapfile -t partial_calls <"$GLAB_TEST_LOG"
[[ ${#partial_calls[@]} -eq 2 ]] || fail "partial mark failure did not stop at the failing notification"

mkdir "$sandbox/failbin"
cat >"$sandbox/failbin/mktemp" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$sandbox/failbin/mktemp"
set +e
mark_setup_failed=$(PATH="$sandbox/failbin:$sandbox:$PATH" "$HELPER" --mark-notification-read 123)
mark_setup_status=$?
fetch_setup_failed=$(PATH="$sandbox/failbin:$sandbox:$PATH" "$HELPER")
fetch_setup_status=$?
set -e
[[ $mark_setup_status -eq 1 && $fetch_setup_status -eq 1 ]] || fail "temporary-storage failures returned an unexpected status"
assert_jq '.state == "error"' "$mark_setup_failed" "single mark setup failure reports an error"
assert_jq '.state == "error"' "$fetch_setup_failed" "refresh setup failure reports an error"

# The pipeline scan runs in xargs subshells, which only see exported
# functions. An unexported helper there degrades every warning to the generic
# fallback instead of the API's own explanation.
cat >"$sandbox/glab" <<'GLAB'
#!/usr/bin/env bash
if [[ $1 == config ]]; then exit 0; fi
if [[ $1 == auth ]]; then exit 0; fi
if [[ $1 == api && $2 == graphql ]]; then
  if [[ $* == *authoredMergeRequests* ]]; then
    printf '%s\n' '{"data":{"currentUser":{"username":"octocat","authoredMergeRequests":{"count":0,"nodes":[]}}}}'
    exit 0
  fi
  cat <<'JSON'
{"data":{"projects":{"count":1,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"gid://gitlab/Project/1","fullPath":"octocat/hello","webUrl":"https://example.gitlab.test/octocat/hello","archived":false,"isForked":false,"starCount":1,"forksCount":0,"lastActivityAt":"2026-01-01T00:00:00Z","issues":{"count":0},"mergeRequests":{"count":0}}]}}}
JSON
  exit 0
fi
endpoint=${*: -1}
if [[ $endpoint == projects/1/pipelines* ]]; then
  echo "HTTP 403: insufficient_scope" >&2
  exit 1
fi
printf '%s\n' '[]'
GLAB
chmod +x "$sandbox/glab"
scoped=$(PATH="$sandbox:$PATH" "$HELPER" --scan all)
assert_jq '(.warnings|length) > 0 and (.warnings[0]|test("403"))' "$scoped" "pipeline scan warnings keep the API error text"

# --hostname must reach the pipeline scan even though it runs in
# xargs-spawned subshells that cannot inherit a bash array.
: >"$GLAB_TEST_LOG"
cat >"$sandbox/glab" <<'GLAB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GLAB_TEST_LOG"
args=("$@")
# The helper places --hostname right after `api`; strip it here so the rest
# of this stub can dispatch on fixed positions like the other fixtures do.
if [[ ${args[0]} == api && ${args[1]} == --hostname ]]; then args=(api "${args[@]:3}"); fi
if [[ ${args[0]} == config ]]; then exit 0; fi
if [[ ${args[0]} == auth ]]; then exit 0; fi
if [[ ${args[0]} == api && ${args[1]} == graphql ]]; then
  if [[ ${args[*]} == *authoredMergeRequests* ]]; then
    printf '%s\n' '{"data":{"currentUser":{"username":"octocat","authoredMergeRequests":{"count":0,"nodes":[]}}}}'
    exit 0
  fi
  cat <<'JSON'
{"data":{"projects":{"count":1,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"gid://gitlab/Project/1","fullPath":"octocat/hello","webUrl":"https://example.gitlab.test/octocat/hello","archived":false,"isForked":false,"starCount":1,"forksCount":0,"lastActivityAt":"2026-01-01T00:00:00Z","issues":{"count":0},"mergeRequests":{"count":0}}]}}}
JSON
  exit 0
fi
printf '%s\n' '[]'
GLAB
chmod +x "$sandbox/glab"
out_hostname=$(PATH="$sandbox:$PATH" "$HELPER" --scan all --hostname example.gitlab.test)
assert_jq '.state == "ready"' "$out_hostname" "a hostname-scoped run still succeeds"
grep -q '^api --hostname example.gitlab.test --paginate projects/1/pipelines' "$GLAB_TEST_LOG" || fail "--hostname was dropped from the pipeline scan subshell"

echo "gitlab helper tests passed"
