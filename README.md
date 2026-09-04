# Omarchy Forge

Your GitHub or GitLab work, directly in the Omarchy bar — one widget, one provider at a time.

**Forge** turns a single bar icon into a fast, keyboard-friendly command center for everything that needs your attention on GitHub or GitLab (gitlab.com or a self-hosted instance) — without keeping another browser tab open. It started as [Omarchy GitHub](https://github.com/robzolkos/omarchy-github) by Rob Zolkos, was ported to GitLab, and is now both at once: pick **Provider** in settings and the whole dashboard — terminology, icon, and deep links included — follows.

If you use both GitHub and a self-hosted GitLab, install this plugin twice under different local checkouts (see [Running two instances](#running-two-instances)) rather than expecting one widget to show both at once; that was a deliberate scope decision, not a limitation to work around.

## Everything waiting for you, in one panel

The dashboard is ordered by urgency so the most actionable work appears first:

- **Unread notifications** — mentions, assignments, and review requests (GitHub notifications / GitLab to-dos). Open the related item, mark it done in place, or clear everything on screen
- **Review requests** — pull/merge requests waiting on your review
- **My pull/merge requests** — track what you opened and the state of its checks or pipeline
- **Assigned issues** — keep track of open issues assigned to you
- **Running Actions/pipelines** — monitor active CI runs
- **Recent failed Actions/pipelines** — jump directly to failed runs
- **Repositories/projects** — browse what you own, and optionally everything you have wider access to, with open issue, open PR/MR, star, and active-run counts

Search, metric filters, and sorting make even large accounts manageable. Filter to repositories/projects with issues, PRs/MRs, stars, or active runs, then sort by the metric that matters.

## Highlights

- Native Omarchy Quattro bar widget with a provider-matched icon
- **Provider** setting switches the entire dashboard between GitHub and GitLab (gitlab.com or self-hosted) — no reinstall needed
- Compact previews that keep busy accounts readable
- Direct links to notifications, pull/merge requests, issues, runs, and repositories/projects
- One-click mark-as-read/done, confirmed by the provider before removal
- Bulk mark-as-read behind a confirmation step, bounded to what's on screen
- Complete paginated repository/project and notification fetching
- Configurable Actions/pipeline scanning with bounded concurrency
- Graceful partial results when an endpoint or repository/project is unavailable
- Explicit logged-out, missing-CLI, loading, and error states
- Mouse and keyboard navigation throughout
- Uses the existing `gh`/`glab` CLI credential store — no token configuration or secret files

## Requirements

- Omarchy Quattro with shell plugin support
- [`jq`](https://jqlang.github.io/jq/)
- A Nerd Font; Omarchy includes one by default
- Whichever CLI matches the provider you select: [`gh`](https://cli.github.com/) for GitHub, or [`glab`](https://gitlab.com/gitlab-org/cli) for GitLab. You only need the one you actually use.

Authenticate the CLI for your provider before installing.

GitHub:

```bash
gh auth login
gh auth status
```

GitLab, for gitlab.com:

```bash
glab auth login
glab auth status
```

GitLab, for a self-hosted instance — sign in against its hostname and set it as the default host so the widget picks it up automatically:

```bash
glab auth login --hostname gitlab.example.com
glab config set -g host gitlab.example.com
glab auth status --hostname gitlab.example.com
```

The default `gh`/`glab` API scope is enough to read notifications, pull/merge requests, issues, runs, and repositories/projects, and to mark notifications/to-dos read. Forge delegates authentication entirely to the CLI. It does not read, copy, log, or persist your token.

## Install

`omarchy plugin add` clones a git URL's **default branch**; it has no flag to
select a different one. This unified plugin lives on the `forge` branch of
this fork (the default `main` branch is still Rob Zolkos's original
GitHub-only plugin). Install from a local checkout of `forge` instead of the
bare GitHub URL:

```bash
git clone --branch forge https://github.com/pranavbabu/omarchy-github.git /tmp/omarchy-forge
omarchy plugin add /tmp/omarchy-forge --enable
```

Once `forge` is merged to (or replaces) the repository's default branch, the
direct form works and `omarchy plugin update` tracks it normally:

```bash
omarchy plugin add https://github.com/pranavbabu/omarchy-github.git --enable
```

The widget defaults to the right side of the bar and to **Provider: GitHub**. To choose its position interactively:

```bash
omarchy bar move pranavbabu.forge
```

Switch to GitLab from the panel's own settings (gear icon), or from the command line:

```bash
omarchy bar set pranavbabu.forge provider "GitLab"
```

Confirm the installation:

```bash
omarchy plugin list | grep pranavbabu.forge
```

If your `glab` default host is not the GitLab instance you want this widget to use, set it explicitly in the widget's own settings rather than changing `glab`'s global default:

```bash
omarchy bar set pranavbabu.forge gitlabHost "gitlab.example.com"
```

### Update

```bash
omarchy plugin update pranavbabu.forge
```

If your Omarchy version only supports updating all third-party plugins:

```bash
omarchy plugin update
```

### Remove

```bash
omarchy plugin remove pranavbabu.forge
```

### Running two instances

Omarchy plugin ids are unique per install, and one widget shows one provider at a time by design (see the top of this README). Watching GitHub and GitLab simultaneously would mean installing from two local checkouts with the `id` in each `manifest.json` changed to something distinct before committing. This isn't a supported or tested configuration — `omarchy plugin update` won't recognise a renamed copy as tracking this repository — so treat it as a starting point to experiment with, not a documented procedure.

## Controls

| Input | Action |
| --- | --- |
| Left click the bar icon | Open or close the dashboard |
| Right or middle click the bar icon | Refresh |
| Click a row | Open it on GitHub/GitLab; notification rows are also marked read |
| Gear button in the panel header | Open the settings page |
| Check button on a notification | Mark it read/done immediately, then confirm with the provider |
| **Mark all read** in the notifications footer | Arm the bulk mark-as-read |
| **Confirm?** on the armed button | Mark every notification on screen read |
| `j` / `k` or arrow keys | Move through visible rows |
| `Enter` / `Space` | Open the highlighted row |
| `m` | Mark the highlighted notification read |
| `/` | Focus repository/project search |
| `r` | Refresh |
| `Escape` in search | Clear search and return to row navigation |
| `Escape` elsewhere | Close the panel |

Rows open through `omarchy-launch-webapp` by default, so the provider gets a dedicated app window rather than a tab in an already-crowded browser. That helper targets Chromium-based default browsers and falls back to `chromium.desktop`; if you have no Chromium-based browser, switch **Open links** to **Browser tab** and rows open through `omarchy-launch-browser` instead.

Activity sections show five items initially and expand to a bounded list of 25. **Open in GitHub**/**Open in GitLab** takes you to the corresponding dashboard view where one is available.

The notifications footer also carries **Mark all read**. The first click captures the displayed snapshot and changes the label to **Confirm?**; only the second click sends the request. The confirmation lapses after a few seconds, when the panel closes, when a refresh changes the notification list, and whenever another mark is running. GitHub marks everything before a timestamp boundary in one request (preserving same-second arrivals by re-marking the exact fetched boundary IDs); GitLab has no such boundary endpoint, so it submits the exact set of displayed to-do ids instead — a to-do that arrives mid-confirmation is simply not in that set and stays unread, which is strictly safer than GitHub's same-second edge case. Either way the dashboard refreshes after every attempt.

## Repository/project dashboard

Every listed repository/project includes:

- Open issue count
- Open pull/merge request count
- Star count
- Active run count, when present
- Last-activity time

Use the filter chips to show all repositories/projects or only ones with a non-zero issue, PR/MR, star, or active-run count. Sort by update time, name, or any metric. Search always runs against the complete fetched list, even when rendered rows are capped.

## Settings

The everyday options — **Provider**, **GitLab host**, **Open links**, **Repository scope**, **Refresh interval**, and the archived, forked, and unlit-icon toggles — are also editable in the panel itself through the gear button in the header. Changes are written to the widget's entry in `shell.json` and apply immediately. The remaining options stay in Omarchy's bar widget settings.

| Setting | Default |
| --- | --- |
| Provider | **GitHub** |
| GitLab host | *(blank — used only when Provider is GitLab; uses `glab`'s configured default host)* |
| Refresh interval | 900 seconds (15 minutes) |
| Open links | **Web app window** |
| Include archived repositories/projects | Off |
| Include forked repositories/projects | Off |
| Repository scope | **Owned** |
| Include review requests and issues from archived repositories/projects | Off |
| Include review requests on drafts | Off |
| Maximum displayed repositories/projects | 25 |
| Actions/pipeline scan | **Recent** |
| Recent scan limit | 15 |
| Scan concurrency | 6 |
| Failed window | 7 days |
| Maximum failed Actions/pipelines | 20 |
| Keep the bar icon unlit | Off |

**Repository scope** controls both the repository/project dashboard and the candidate set for Actions/pipeline scanning. **Wider** is opt-in: on GitHub it adds every organization repository you can reach; on GitLab it adds every group and subgroup project you belong to, not only ones in your personal namespace. With the default **Recent** scan, requests remain capped to the 15 most recently active repositories/projects in that wider scope.

**All** scan is also opt-in and starts several paginated run/pipeline request streams per repository/project on every refresh. Combining it with the **Wider** scope can consume substantial API capacity on a large account or instance. Use **Recent** or **Off** for a bounded scan, and increase the refresh interval when broader monitoring is required.

Set these options from the command line after installing the plugin:

```bash
omarchy bar set pranavbabu.forge repositoryScope "Wider"
omarchy bar set pranavbabu.forge scanBehavior "Recent"
```

Restore the narrowest behavior with:

```bash
omarchy bar set pranavbabu.forge repositoryScope "Owned"
omarchy bar set pranavbabu.forge scanBehavior "Off"
```

Review requests and assigned issues from archived repositories/projects are hidden by default because an archived one is read-only. Review requests on draft pull/merge requests are also hidden by default, while teams that use drafts for early feedback can include them. Each behavior has its own setting.

## Local development

From an existing checkout, validate and test the plugin:

```bash
omarchy plugin validate .
tests/github-helper-test.sh
tests/gitlab-helper-test.sh
tests/schema-test.sh
tests/panel-source-test.sh
tests/service-source-test.sh
```

Install that checkout for local iteration. `plugin add` clones from the
checkout's git history, not its working tree, so commit before running it or
the install will silently pick up whatever was last committed:

```bash
git add -A && git commit -m "wip"   # plugin add clones HEAD, not uncommitted edits
omarchy plugin add "$PWD" --enable
```

After further edits, `omarchy plugin update <id> --yes` re-clones from the
same local path and needs a new commit to have anything to pull. The shell
then watches the installed copy's files, making QML iteration fast — for most
edits. If a change doesn't seem to take effect (new IPC functions not showing
in `qs ipc show`, or a fix that still looks broken after `plugin update` and
even `plugin disable`/`plugin enable`), don't trust that as a verdict on the
change: `disable`/`enable` was observed, while building this, to keep serving
a stale component instead of rebuilding it. Confirm with `omarchy restart
shell` first — it's slower (it blips the whole bar) but it's the only thing
that reliably reflects the file on disk.

## How it works

`Service.qml` picks a helper script by the **Provider** setting — `omarchy-github-fetch` (calls GitHub through `gh api`) or `omarchy-gitlab-fetch` (calls GitLab through `glab api`) — and processes either one's output identically, because both helpers emit the same top-level JSON shape (`tests/schema-test.sh` is the contract test for this). Everything in `Service.qml` and `Panel.qml` is provider-agnostic except: which helper binary to run, the two genuinely different bulk-mark-as-read implementations (GitHub's timestamp boundary vs. GitLab's id snapshot), and a small per-provider terminology/icon table in `Panel.qml`.

- GraphQL retrieves every repository/project in the configured scope with exact open issue and pull/merge request counts, star and fork counts, and archived state, in one paginated query.
- GraphQL retrieves your authored pull/merge requests together with the head commit's check rollup or head pipeline's status, so that state costs no extra request. `omarchy-gitlab-fetch` folds GitLab's pipeline status enum down into the FAILURE/PENDING/SUCCESS/NONE vocabulary GitHub's check rollup already used, so `Service.qml`'s check-state logic needs no provider branch.
- REST retrieves notifications/to-dos, review-requested and assigned-to-you pull/merge requests and issues, and per-repository/project runs.
- Status-specific, paginated run requests prevent busy repositories/projects from hiding an active run.
- Finished runs are bounded to the configured failure window.
- Independent requests allow successful sections to remain available when one endpoint fails.

Run either helper directly to inspect its JSON output:

```bash
./omarchy-github-fetch --scan recent --scan-limit 15 | jq
./omarchy-gitlab-fetch --scan recent --scan-limit 15 | jq
```

### Differences between the two providers

A few things do not have a like-for-like equivalent on the other side:

- **Bulk mark-as-read is not identical.** GitHub's `/notifications` endpoint accepts a "mark everything read before this timestamp" call; GitLab's to-do API only marks individual to-dos or every to-do you have, with nothing in between. GitLab bulk marking here submits the exact set of ids displayed on screen instead of a time boundary — a to-do that arrives mid-confirmation is never touched, which is strictly safer than GitHub's same-second edge case.
- **No rate-limit footer on GitLab.** GitHub's GraphQL API returns a `rateLimit` field on every request, shown in the panel footer; self-hosted GitLab instances typically do not expose an equivalent, so the field is always `null` for GitLab and the footer line stays hidden.
- **Dashboard deep links are best-effort on GitLab.** GitHub's are fixed URLs (`/notifications`, `/pulls/review-requested`, `/pulls`, `/issues/assigned`). GitLab's use its documented `/dashboard/todos`, `/dashboard/merge_requests`, and `/dashboard/issues` paths with username query filters; very old GitLab versions may ignore a filter and show the unfiltered list instead.
- **Icon glyphs come from two different Nerd Fonts ranges**, matching what each original project used: GitHub's Octocat and pull-request glyph are legacy Private Use Area codepoints (U+E000–U+F8FF); GitLab's icon and merge-request glyph are Nerd Fonts v3's newer Supplementary PUA-A range (≥ U+F0000). Both ranges render correctly in a current Nerd Font.

## License

MIT

Started as [Omarchy GitHub](https://github.com/robzolkos/omarchy-github) by Rob Zolkos (MIT licensed), ported to GitLab, then unified into one provider-switchable widget.
