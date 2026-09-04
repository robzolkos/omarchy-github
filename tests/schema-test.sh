#!/usr/bin/env bash
# Contract test: omarchy-github-fetch and omarchy-gitlab-fetch must emit the
# same top-level shape, and the same required fields per item, so Service.qml
# can apply() either payload without a per-provider parsing branch. Real,
# non-shareable differences (e.g. GitHub's PR "conclusion" has no GitLab
# equivalent) are allowed to diverge beyond this required subset.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() { echo "FAIL: $*" >&2; exit 1; }

TOP_LEVEL_KEYS='["schemaVersion","state","message","provider","host","login","repositoryScope","fetchedAt","notifications","reviewRequests","assignedIssues","authored","authoredTotal","runs","failedRuns","repositories","warnings","rateLimit"]'

run_github() {
  local sandbox=$1
  ln -sf "$(command -v jq)" "$sandbox/jq"
  cat >"$sandbox/gh" <<'GH'
#!/usr/bin/env bash
if [[ $1 == auth ]]; then exit 0; fi
if [[ $1 == api && $2 == graphql ]]; then
  if [[ $* == *author:@me* ]]; then
    cat <<'JSON'
{"data":{"search":{"issueCount":1,"nodes":[{"number":7,"title":"Ship it","url":"https://github.com/octocat/hello/pull/7","updatedAt":"2026-01-05T00:00:00Z","isDraft":false,"repository":{"nameWithOwner":"octocat/hello"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}}]}}}
JSON
    exit 0
  fi
  cat <<'JSON'
{"data":{"viewer":{"login":"octocat","repositories":{"nodes":[{"name":"hello","nameWithOwner":"octocat/hello","url":"https://github.com/octocat/hello","isArchived":false,"isFork":false,"stargazerCount":1,"updatedAt":"2026-01-01T00:00:00Z","issues":{"totalCount":1},"pullRequests":{"totalCount":1}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"remaining":100,"resetAt":"2026-01-01T01:00:00Z","cost":1}}}
JSON
  exit 0
fi
endpoint=${*: -1}
if [[ $endpoint == /notifications* ]]; then
  cat <<'JSON'
[{"id":"123","unread":true,"reason":"mention","updated_at":"2026-01-03T00:00:00Z","repository":{"full_name":"octocat/hello","html_url":"https://github.com/octocat/hello"},"subject":{"title":"Review this","type":"PullRequest","url":"https://api.github.com/repos/octocat/hello/pulls/7"}}]
JSON
  exit 0
fi
if [[ $endpoint == /search/issues\?q=is%3Aopen+is%3Apr* ]]; then
  echo '{"items":[{"id":71,"number":7,"title":"Please review","repository_url":"https://api.github.com/repos/octocat/hello","html_url":"https://github.com/octocat/hello/pull/7","updated_at":"2026-01-02T00:00:00Z","user":{"login":"friend"}}]}'
  exit 0
fi
if [[ $endpoint == /search/issues\?q=is%3Aopen+is%3Aissue* ]]; then
  echo '{"items":[{"id":81,"number":8,"title":"Fix it","repository_url":"https://api.github.com/repos/octocat/hello","html_url":"https://github.com/octocat/hello/issues/8","updated_at":"2026-01-02T00:00:00Z","user":{"login":"friend"}}]}'
  exit 0
fi
if [[ $endpoint == /repos/octocat/hello/actions/runs* ]]; then
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ $endpoint == *status=in_progress* ]]; then
    echo "{\"workflow_runs\":[{\"id\":10,\"name\":\"CI\",\"display_title\":\"Build\",\"status\":\"in_progress\",\"conclusion\":null,\"event\":\"push\",\"head_branch\":\"main\",\"html_url\":\"https://github.com/octocat/hello/actions/runs/10\",\"created_at\":\"$now\",\"updated_at\":\"$now\"}]}"
  elif [[ $endpoint == *status=completed* ]]; then
    echo "{\"workflow_runs\":[{\"id\":11,\"name\":\"Test\",\"display_title\":\"Test\",\"status\":\"completed\",\"conclusion\":\"failure\",\"event\":\"push\",\"head_branch\":\"main\",\"html_url\":\"https://github.com/octocat/hello/actions/runs/11\",\"created_at\":\"$now\",\"updated_at\":\"$now\"}]}"
  else
    echo '{"workflow_runs":[]}'
  fi
  exit 0
fi
exit 1
GH
  chmod +x "$sandbox/gh"
  PATH="$sandbox:$PATH" "$ROOT/omarchy-github-fetch" --scan all --failed-days 30
}

run_gitlab() {
  local sandbox=$1
  ln -sf "$(command -v jq)" "$sandbox/jq"
  ln -sf "$(command -v date)" "$sandbox/date"
  ln -sf "$(command -v xargs)" "$sandbox/xargs"
  ln -sf "$(command -v bash)" "$sandbox/bash"
  ln -sf "$(command -v sed)" "$sandbox/sed"
  ln -sf "$(command -v tr)" "$sandbox/tr"
  ln -sf "$(command -v cut)" "$sandbox/cut"
  ln -sf "$(command -v grep)" "$sandbox/grep"
  ln -sf "$(command -v sort)" "$sandbox/sort"
  ln -sf "$(command -v mktemp)" "$sandbox/mktemp"
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
if [[ $1 == api && $2 == graphql ]]; then
  if [[ $* == *authoredMergeRequests* ]]; then
    cat <<'JSON'
{"data":{"currentUser":{"username":"octocat","authoredMergeRequests":{"count":1,"nodes":[{"iid":"7","title":"Ship it","webUrl":"https://example.gitlab.test/octocat/hello/-/merge_requests/7","updatedAt":"2026-01-05T00:00:00Z","draft":false,"project":{"fullPath":"octocat/hello"},"headPipeline":{"status":"FAILED"}}]}}}
JSON
    exit 0
  fi
  cat <<'JSON'
{"data":{"projects":{"count":1,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"gid://gitlab/Project/1","fullPath":"octocat/hello","webUrl":"https://example.gitlab.test/octocat/hello","archived":false,"isForked":false,"starCount":1,"forksCount":0,"lastActivityAt":"2026-01-01T00:00:00Z","issues":{"count":1},"mergeRequests":{"count":1}}]}}}
JSON
  exit 0
fi
endpoint=${*: -1}
if [[ $endpoint == todos\?state=pending* ]]; then
  echo '[{"id":123,"action_name":"mentioned","updated_at":"2026-01-03T00:00:00Z","project":{"path_with_namespace":"octocat/hello"},"target_type":"MergeRequest","target":{"title":"Review this"},"target_url":"https://example.gitlab.test/octocat/hello/-/merge_requests/7"}]'
  exit 0
fi
if [[ $endpoint == merge_requests\?scope=all* ]]; then
  echo '[{"id":71,"iid":7,"title":"Please review","references":{"full":"octocat/hello!7"},"web_url":"https://example.gitlab.test/octocat/hello/-/merge_requests/7","updated_at":"2026-01-02T00:00:00Z","author":{"username":"friend"},"draft":false}]'
  exit 0
fi
if [[ $endpoint == issues\?scope=all* ]]; then
  echo '[{"id":81,"iid":8,"title":"Fix it","references":{"full":"octocat/hello#8"},"web_url":"https://example.gitlab.test/octocat/hello/-/issues/8","updated_at":"2026-01-02T00:00:00Z","author":{"username":"friend"}}]'
  exit 0
fi
if [[ $endpoint == projects/1/pipelines\?status=running* ]]; then
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "[{\"id\":10,\"status\":\"running\",\"source\":\"push\",\"ref\":\"main\",\"web_url\":\"https://example.gitlab.test/octocat/hello/-/pipelines/10\",\"created_at\":\"$now\",\"updated_at\":\"$now\"}]"
  exit 0
fi
if [[ $endpoint == projects/1/pipelines\?status=failed* ]]; then
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "[{\"id\":11,\"status\":\"failed\",\"source\":\"push\",\"ref\":\"main\",\"web_url\":\"https://example.gitlab.test/octocat/hello/-/pipelines/11\",\"created_at\":\"$now\",\"updated_at\":\"$now\"}]"
  exit 0
fi
if [[ $endpoint == projects/*/pipelines* ]]; then
  echo '[]'
  exit 0
fi
exit 1
GLAB
  chmod +x "$sandbox/glab"
  PATH="$sandbox:$PATH" "$ROOT/omarchy-gitlab-fetch" --scan all --failed-days 30
}

github_sandbox=$(mktemp -d)
gitlab_sandbox=$(mktemp -d)
trap 'rm -rf "$github_sandbox" "$gitlab_sandbox"' EXIT

github_out=$(run_github "$github_sandbox")
gitlab_out=$(run_gitlab "$gitlab_sandbox")

echo "$github_out" | jq -e '.state == "ready"' >/dev/null || fail "github fixture did not reach ready state: $github_out"
echo "$gitlab_out" | jq -e '.state == "ready"' >/dev/null || fail "gitlab fixture did not reach ready state: $gitlab_out"

github_keys=$(echo "$github_out" | jq -Sc '. | keys')
gitlab_keys=$(echo "$gitlab_out" | jq -Sc '. | keys')
expected_keys=$(echo "$TOP_LEVEL_KEYS" | jq -Sc '. | sort')
[[ $github_keys == "$expected_keys" ]] || fail "omarchy-github-fetch top-level keys $github_keys do not match the canonical set $expected_keys"
[[ $gitlab_keys == "$expected_keys" ]] || fail "omarchy-gitlab-fetch top-level keys $gitlab_keys do not match the canonical set $expected_keys"

echo "$github_out" | jq -e '.provider == "github"' >/dev/null || fail "github payload does not self-identify its provider"
echo "$gitlab_out" | jq -e '.provider == "gitlab"' >/dev/null || fail "gitlab payload does not self-identify its provider"

assert_item_keys() {
  local label=$1 section=$2 keys=$3
  local missing
  missing=$(jq -nc --argjson gh "$github_out" --argjson gl "$gitlab_out" --argjson keys "$keys" --arg section "$section" '
    [$gh, $gl] | map(.[$section][0]) as $items |
    $keys | map(select(. as $k | ($items | map(has($k)) | any) | not))
  ')
  [[ $missing == "[]" ]] || fail "$label section \"$section\" is missing required key(s) $missing in one provider's payload"
}

assert_item_keys "notifications" notifications '["id","reason","updatedAt","repository","title","type","url"]'
assert_item_keys "reviewRequests" reviewRequests '["id","number","title","repository","url","updatedAt","user","draft"]'
assert_item_keys "assignedIssues" assignedIssues '["id","number","title","repository","url","updatedAt","user","draft"]'
assert_item_keys "authored" authored '["id","number","title","repository","url","updatedAt","draft","checks"]'
assert_item_keys "runs" runs '["id","repository","name","status","event","branch","url","createdAt","updatedAt"]'
assert_item_keys "failedRuns" failedRuns '["id","repository","name","status","event","branch","url","createdAt","updatedAt"]'
assert_item_keys "repositories" repositories '["name","nameWithOwner","url","archived","fork","stars","issues","prs","updatedAt","activeRuns"]'

echo "schema tests passed"
