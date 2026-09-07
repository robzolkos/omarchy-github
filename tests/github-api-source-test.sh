#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_text=$(<"$root/GitHubApi.qml")

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { [[ $source_text == *"$1"* ]] || fail "$2"; }
excludes() { [[ $source_text != *"$1"* ]] || fail "$2"; }

contains 'runtime.execute("bash", "gh", arguments)' "GitHub calls do not use structured command execution"
contains '["auth", "status", "--hostname", "github.com"]' "authentication can escape the fixed GitHub host"
contains '["api", "--method", "PATCH", "/notifications/threads/" + id]' "single notification marking is missing"
contains '["api", "--method", "PUT", "/notifications", "-f", "last_read_at=" + before]' "bulk marking is missing its bounded timestamp"
contains 'var statuses = ["in_progress", "queued", "waiting", "requested", "pending"]' "active Actions states drifted"
contains 'while (job.actionActive < job.options.actionConcurrency' "Actions requests are not concurrency bounded"
contains 'pageInfo.hasNextPage === true && /^[A-Za-z0-9_-]{1,256}$/' "repository cursors are not locally shape checked"
contains 'gh[pousr]_[A-Za-z0-9_]{20,}' "GitHub token errors are not redacted"
contains 'github_pat_[A-Za-z0-9_]{20,}' "fine-grained GitHub tokens are not redacted"
contains 'callback(exitCode === 0, String(envelope.stdout || ""), standardError, exitCode)' "executor envelopes are not checked"
excludes 'Quickshell' "GitHub adapter imports ambient Quickshell authority"
excludes 'BrokerProcess' "GitHub adapter recreated a Process facade"
excludes 'omarchy-github-fetch' "GitHub adapter executes the plugin-owned helper"
excludes 'runtime.invoke("bash.execute"' "GitHub adapter bypasses the structured execute API"

printf '%s\n' 'github api source tests passed'
