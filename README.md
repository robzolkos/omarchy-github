# Omarchy GitLab

Your GitLab work, directly in the Omarchy bar — for gitlab.com or a self-hosted instance.

**Omarchy GitLab** turns the GitLab icon in your bar into a fast, keyboard-friendly command center for everything that needs your attention — without keeping another browser tab open. It is a GitLab port of [Omarchy GitHub](https://github.com/robzolkos/omarchy-github) by Rob Zolkos: the same dashboard, panel, and keyboard model, rebuilt on GitLab's API and CLI.

## Everything waiting for you, in one panel

The dashboard is ordered by urgency so the most actionable work appears first:

- **Unread notifications** — GitLab's to-do list: mentions, assignments, and review requests. Open the related item, mark it done in place, or clear everything on screen
- **Review requests** — see merge requests waiting on your review
- **My merge requests** — track the merge requests you opened and the state of their pipeline
- **Assigned issues** — keep track of open issues assigned to you
- **Running pipelines** — monitor active CI/CD pipelines
- **Recent failed pipelines** — jump directly to failed runs
- **Projects** — browse the projects you own, and optionally every project you are a member of, with open issue, open MR, star, and active pipeline counts

Project search, metric filters, and sorting make even large GitLab accounts manageable. Filter to projects with issues, MRs, stars, or active pipelines, then sort by the metric that matters.

## Highlights

- Native Omarchy Quattro bar widget with a GitLab icon
- Works against gitlab.com or any self-hosted GitLab instance
- Compact previews that keep busy accounts readable
- Direct links to notifications, merge requests, issues, pipelines, and projects
- One-click notification mark-as-done, confirmed by GitLab before removal
- Bulk mark-as-done behind a confirmation step, bounded to the notifications on screen
- Complete paginated project and notification fetching
- Configurable pipeline scanning with bounded concurrency
- Graceful partial results when an endpoint or project is unavailable
- Explicit logged-out, missing-CLI, loading, and error states
- Mouse and keyboard navigation throughout
- Uses the existing GitLab CLI (`glab`) credential store — no token configuration or secret files

## Requirements

- Omarchy Quattro with shell plugin support
- [`glab`](https://gitlab.com/gitlab-org/cli) on `PATH`
- [`jq`](https://jqlang.github.io/jq/)
- A Nerd Font; Omarchy includes one by default

Authenticate the GitLab CLI before installing. For gitlab.com:

```bash
glab auth login
glab auth status
```

For a self-hosted instance, sign in against its hostname and set it as the default host so the widget picks it up automatically:

```bash
glab auth login --hostname gitlab.example.com
glab config set -g host gitlab.example.com
glab auth status --hostname gitlab.example.com
```

The default `api` scope is enough to read notifications, merge requests, issues, pipelines, and projects, and to mark to-dos done.

Omarchy GitLab delegates authentication entirely to `glab`. It does not read, copy, log, or persist your GitLab token.

## Install

`omarchy plugin add` clones a git URL's **default branch**; it has no flag to
select a different one. While this GitLab port lives on the `gitlab-port`
branch of a fork that still has the original GitHub plugin on `main`, install
it from a local checkout of that branch instead of the bare GitHub URL:

```bash
git clone --branch gitlab-port https://github.com/pranavbabu/omarchy-github.git /tmp/omarchy-gitlab
omarchy plugin add /tmp/omarchy-gitlab --enable
```

Once `gitlab-port` is merged to (or replaces) the repository's default
branch, the direct form works and `omarchy plugin update` tracks it normally:

```bash
omarchy plugin add https://github.com/pranavbabu/omarchy-github.git --enable
```

The widget defaults to the right side of the bar. To choose its position interactively:

```bash
omarchy bar move pranavbabu.gitlab
```

Confirm the installation:

```bash
omarchy plugin list | grep pranavbabu.gitlab
```

If your `glab` default host is not the instance you want this widget to use, set it explicitly in the widget's own settings (gear icon in the panel, or `omarchy bar set`) rather than changing `glab`'s global default:

```bash
omarchy bar set pranavbabu.gitlab gitlabHost "gitlab.example.com"
```

### Update

```bash
omarchy plugin update pranavbabu.gitlab
```

If your Omarchy version only supports updating all third-party plugins:

```bash
omarchy plugin update
```

### Remove

```bash
omarchy plugin remove pranavbabu.gitlab
```

## Controls

| Input | Action |
| --- | --- |
| Left click the GitLab icon | Open or close the dashboard |
| Right or middle click the GitLab icon | Refresh |
| Click a row | Open it on GitLab; notification rows are also marked done |
| Gear button in the panel header | Open the settings page |
| Check button on a notification | Mark it done immediately, then confirm with GitLab |
| **Mark all read** in the notifications footer | Arm the bulk mark-as-done |
| **Confirm?** on the armed button | Mark every notification on screen done |
| `j` / `k` or arrow keys | Move through visible rows |
| `Enter` / `Space` | Open the highlighted row |
| `m` | Mark the highlighted notification done |
| `/` | Focus project search |
| `r` | Refresh |
| `Escape` in search | Clear search and return to row navigation |
| `Escape` elsewhere | Close the panel |

Rows open through `omarchy-launch-webapp` by default, so GitLab gets a dedicated app window rather than a tab in an already-crowded browser. That helper targets Chromium-based default browsers and falls back to `chromium.desktop`; if you have no Chromium-based browser, switch **Open links** to **Browser tab** and rows open through `omarchy-launch-browser` instead.

Activity sections show five items initially and expand to a bounded list of 25. **Open in GitLab** takes you to the corresponding dashboard view where one is available.

The notifications footer also carries **Mark all read**. The first click captures the displayed notification snapshot and changes the label to **Confirm?**; only the second click sends the request. The confirmation lapses after a few seconds, when the panel closes, when a refresh changes the notification list, and whenever another mark is running. GitLab has no "mark everything before a timestamp" endpoint the way GitHub does, so bulk marking submits the exact set of displayed notification ids rather than a time boundary — a notification that arrives mid-confirmation is simply not in that set and stays unread. The dashboard refreshes from GitLab after every attempt.

## Project dashboard

Every listed project includes:

- Open issue count
- Open merge request count
- Star count
- Active pipeline count, when present
- Last-activity time

Use the filter chips to show all projects or only projects with a non-zero issue, MR, star, or active pipeline count. Sort by update time, name, or any metric. Search always runs against the complete fetched project list, even when rendered rows are capped.

## Settings

The everyday options — **GitLab host**, **Open links**, **Project scope**, **Refresh interval**, and the archived, forked, and unlit-icon toggles — are also editable in the panel itself through the gear button in the header. Changes are written to the widget's entry in `shell.json` and apply immediately. The remaining options stay in Omarchy's bar widget settings.

| Setting | Default |
| --- | --- |
| GitLab host | *(blank — uses `glab`'s configured default host)* |
| Refresh interval | 900 seconds (15 minutes) |
| Open links | **Web app window** |
| Include archived projects | Off |
| Include forked projects | Off |
| Project scope | **Owned** |
| Include review requests and issues from archived projects | Off |
| Include review requests on drafts | Off |
| Maximum displayed projects | 25 |
| Pipeline scan | **Recent projects** |
| Recent project scan limit | 15 |
| Pipeline scan concurrency | 6 |
| Failed pipeline window | 7 days |
| Maximum failed pipelines | 20 |
| Keep the bar icon unlit | Off |

**Project scope** controls both the project dashboard and the candidate projects for pipeline scanning. **Member of** is opt-in and includes every group and subgroup project you belong to, not only ones in your personal namespace. With the default **Recent projects** scan, pipeline requests remain capped to the 15 most recently active projects in that wider scope.

**All projects** is also opt-in and starts six paginated pipeline request streams per project on every refresh. Combining it with the **Member of** scope can consume substantial GitLab API capacity on a large instance. Use **Recent projects** or **Off** for a bounded scan, and increase the refresh interval when broader monitoring is required.

Set these options from the command line after installing the plugin:

```bash
omarchy bar set pranavbabu.gitlab projectScope "Member of"
omarchy bar set pranavbabu.gitlab pipelineScanBehavior "Recent projects"
```

Restore the narrowest behavior with:

```bash
omarchy bar set pranavbabu.gitlab projectScope "Owned"
omarchy bar set pranavbabu.gitlab pipelineScanBehavior "Off"
```

Review requests and assigned issues from archived projects are hidden by default because an archived project is read-only. Review requests on draft merge requests are also hidden by default, while teams that use drafts for early feedback can include them. Each behavior has its own setting.

## Local development

From an existing checkout, validate and test the plugin:

```bash
omarchy plugin validate .
tests/helper-test.sh
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
then watches the installed copy's files, making QML iteration fast.

## How it works

`Service.qml` schedules an executable helper, `omarchy-gitlab-fetch`, which calls GitLab exclusively through `glab api` and processes responses with `jq`.

- GraphQL retrieves every project in the configured scope (`personal` or `membership`) with exact open issue and merge request counts, star and fork counts, and archived state, in one paginated query.
- GraphQL retrieves your authored merge requests together with the head pipeline's status, so pipeline state costs no extra request. The helper folds GitLab's pipeline status enum down into the FAILURE/PENDING/SUCCESS/NONE vocabulary the panel already understood, so `Service.qml`'s check-state logic is unchanged from the GitHub original.
- REST retrieves to-dos (GitLab's notification inbox), review-requested and assigned-to-you merge requests and issues, and per-project pipelines.
- Status-specific, paginated pipeline requests prevent busy projects from hiding an active run.
- Finished pipelines are bounded to the configured failure window with `updated_after`.
- Independent requests allow successful sections to remain available when one endpoint fails.

Run the helper directly to inspect its JSON output:

```bash
./omarchy-gitlab-fetch --pipeline-scan recent --pipeline-scan-limit 15 | jq
```

### Differences from Omarchy GitHub

A few things do not have a like-for-like GitLab equivalent:

- **Bulk mark-as-read is safer, not identical.** GitHub's `/notifications` endpoint accepts a "mark everything read before this timestamp" call; GitLab's to-do API only marks individual to-dos or every to-do you have, with nothing in between. Marking all as read here submits the exact set of ids displayed on screen instead of a time boundary — a to-do that arrives mid-confirmation is never touched, which is strictly safer than the original's same-second edge case.
- **No rate-limit footer.** GitHub's GraphQL API returns a `rateLimit` field on every request; self-hosted GitLab instances typically do not expose equivalent throttling headers, so the panel's rate-limit line stays hidden (the field is always `null`).
- **Dashboard deep links are best-effort.** The "Open in GitLab" links use GitLab's documented `/dashboard/todos`, `/dashboard/merge_requests`, and `/dashboard/issues` paths with username query filters; very old GitLab versions may ignore a filter and show the unfiltered list instead.
- **Known issue: the GitLab bar icon and a few row icons may not render.** On the machine this was built and tested on, the GitLab icon (originally GitHub's Octocat legacy-PUA codepoint U+F296, then retried as md-gitlab at the newer U+F0BA0) and the merge-request-ish row icons stayed blank in the live bar and panel, despite: the font containing a correct, normal-metrics outline for every codepoint tried; the exact same characters rendering correctly through plain ImageMagick/FreeType against that font file; and a bare `QtQuick.Text` element in a standalone Quickshell process (outside Omarchy's shell entirely) rendering them correctly too. Swapping codepoint ranges (legacy Private Use Area vs. Nerd Fonts' newer ≥ U+F0000 block) did not change the outcome, so the range isn't the cause. The settings gear in the panel header and the trailing `›` chevron on each row — both copied unchanged from the original GitHub plugin, both already in the ≥ U+F0000 range — render fine in the same panel, so it isn't a font, panel, or `Style.font` problem across the board. If you hit this, it's worth checking with Quickshell's own devtools or a QML profiler rather than more codepoint substitution — that's further than static analysis alone could take this.

## License

MIT

Ported from [Omarchy GitHub](https://github.com/robzolkos/omarchy-github) by Rob Zolkos (MIT licensed).
