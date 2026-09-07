import QtQml

// GitHub-specific, authority-free orchestration. Every host effect crosses the
// structured runtime.execute boundary; this object only builds reviewed argv
// vectors and turns returned JSON into the dashboard's presentation model.
QtObject {
    id: root

    property var _calls: []
    property var _job: null
    readonly property bool busy: _job !== null

    readonly property string pullRequestQuery: "query($search:String!) { search(query:$search,type:ISSUE,first:50) { issueCount nodes { ... on PullRequest { number title url updatedAt isDraft repository { nameWithOwner } commits(last:1) { nodes { commit { statusCheckRollup { state } } } } } } } } }"

    function repositoryQuery(scope) {
        var affiliations = scope === "organizations" ? "[OWNER,ORGANIZATION_MEMBER]" : "OWNER";
        return "query($cursor:String) { viewer { login repositories(first:100,after:$cursor,ownerAffiliations:" + affiliations + ",orderBy:{field:UPDATED_AT,direction:DESC}) { nodes { name nameWithOwner url isArchived isFork stargazerCount updatedAt issues(states:OPEN){totalCount} pullRequests(states:OPEN){totalCount} } pageInfo { hasNextPage endCursor } } } rateLimit { remaining resetAt cost } }";
    }

    function sanitizeError(value, fallback) {
        var text = String(value || "");
        text = text.replace(/gh[pousr]_[A-Za-z0-9_]{20,}/g, "[REDACTED]");
        text = text.replace(/github_pat_[A-Za-z0-9_]{20,}/g, "[REDACTED]");
        text = text.replace(/(Authorization:\s*(?:token|Bearer)\s+)[^\s]+/ig, "$1[REDACTED]");
        text = text.replace(/\s+/g, " ").trim();
        return (text || fallback || "GitHub request failed.").slice(0, 240);
    }

    function release(call) {
        var next = [];
        for (var index = 0; index < _calls.length; ++index)
            if (_calls[index] !== call)
                next.push(_calls[index]);
        _calls = next;
    }

    function execute(arguments, callback) {
        var call = runtime.execute("bash", "gh", arguments);
        if (!call) {
            callback(false, "", "Broker request was rejected.", -1);
            return;
        }
        _calls = _calls.concat([call]);
        var done = function() {
            if (!call.finished)
                return;
            try { call.finishedChanged.disconnect(done); } catch (_) {}
            root.release(call);
            if (!call.ok) {
                callback(false, "", root.sanitizeError(call.error, "GitHub request was denied."), -1);
                return;
            }
            var envelope;
            try {
                envelope = JSON.parse(String(call.utf8Text || "{}"));
            } catch (_) {
                callback(false, "", "The command broker returned an unreadable response.", -1);
                return;
            }
            var exitCode = Number(envelope.exitCode);
            var standardError = root.sanitizeError(envelope.stderr, "GitHub request failed.");
            callback(exitCode === 0, String(envelope.stdout || ""), standardError, exitCode);
        };
        if (call.finished)
            done();
        else
            call.finishedChanged.connect(done);
    }

    function emptyData(options) {
        return {
            schemaVersion: 1,
            state: "ready",
            message: "",
            login: "",
            repositoryScope: options.repositoryScope,
            fetchedAt: new Date().toISOString().replace(".000Z", "Z"),
            notifications: [],
            reviewRequests: [],
            assignedIssues: [],
            myPullRequests: [],
            myPullRequestsTotal: 0,
            actions: [],
            failedActions: [],
            repositories: [],
            navigationHandles: {
                notifications: "https://github.com/notifications",
                reviewRequests: "https://github.com/pulls/review-requested",
                pullRequests: "https://github.com/pulls",
                assignedIssues: "https://github.com/issues/assigned"
            },
            warnings: [],
            rateLimit: null
        };
    }

    function pages(raw) {
        var value = JSON.parse(raw || "[]");
        return Array.isArray(value) ? value : [];
    }

    function flattenPages(raw, member) {
        var result = [];
        var values = pages(raw);
        for (var page = 0; page < values.length; ++page) {
            var rows = member ? values[page][member] : values[page];
            if (!Array.isArray(rows))
                continue;
            for (var row = 0; row < rows.length; ++row)
                result.push(rows[row]);
        }
        return result;
    }

    function fetchRestPages(job, label, endpoint, member, callback, page, collected) {
        var pageNumber = page || 1;
        var result = collected || [];
        var arguments = ["api", "-H", "Accept: application/vnd.github+json", endpoint + "&per_page=10&page=" + pageNumber];
        execute(arguments, function(ok, stdout, error) {
            if (!ok) {
                callback(false, result, error);
                return;
            }
            var rows;
            try {
                var value = JSON.parse(stdout || (member ? "{}" : "[]"));
                rows = member ? value[member] : value;
                if (!Array.isArray(rows))
                    throw new Error("not an array");
            } catch (_) {
                callback(false, result, "invalid API response");
                return;
            }
            result = result.concat(rows);
            if (rows.length === 10 && pageNumber < 100) {
                root.fetchRestPages(job, label, endpoint, member, callback, pageNumber + 1, result);
                return;
            }
            if (rows.length === 10)
                root.warn(job, label, "pagination stopped at 100 pages");
            callback(true, result, "");
        });
    }

    function reverseUpdated(rows, field) {
        return rows.sort(function(left, right) {
            return String(right[field] || "").localeCompare(String(left[field] || ""));
        });
    }

    function notificationUrl(item) {
        var repository = item.repository || {};
        var fallback = String(repository.html_url || "");
        if (fallback === "" && repository.full_name)
            fallback = "https://github.com/" + repository.full_name;
        if (fallback === "")
            fallback = "https://github.com/notifications";
        var subject = item.subject || {};
        var api = String(subject.url || "");
        if (subject.type === "PullRequest" && /^https:\/\/api\.github\.com\/repos\/[^/]+\/[^/]+\/pulls\/\d+$/.test(api))
            return api.replace("https://api.github.com/repos/", "https://github.com/").replace("/pulls/", "/pull/");
        if (subject.type === "Issue" && /^https:\/\/api\.github\.com\/repos\/[^/]+\/[^/]+\/issues\/\d+$/.test(api))
            return api.replace("https://api.github.com/repos/", "https://github.com/");
        if (subject.type === "Commit" && /^https:\/\/api\.github\.com\/repos\/[^/]+\/[^/]+\/commits\/[0-9a-fA-F]+$/.test(api))
            return api.replace("https://api.github.com/repos/", "https://github.com/").replace("/commits/", "/commit/");
        if (subject.type === "Discussion" && /^https:\/\/api\.github\.com\/repos\/[^/]+\/[^/]+\/discussions\/\d+$/.test(api))
            return api.replace("https://api.github.com/repos/", "https://github.com/");
        return fallback;
    }

    function parseNotifications(raw) {
        var incoming = flattenPages(raw, "");
        var result = [];
        for (var index = 0; index < incoming.length; ++index) {
            var item = incoming[index] || {};
            if (item.unread !== true)
                continue;
            var subject = item.subject || {};
            var repository = item.repository || {};
            result.push({
                id: String(item.id || ""), reason: String(item.reason || ""),
                updatedAt: String(item.updated_at || ""), repository: String(repository.full_name || ""),
                title: String(subject.title || ""), type: String(subject.type || ""), url: notificationUrl(item)
            });
        }
        return reverseUpdated(result, "updatedAt");
    }

    function parseSearch(raw) {
        var incoming = flattenPages(raw, "items");
        var result = [];
        for (var index = 0; index < incoming.length; ++index) {
            var item = incoming[index] || {};
            result.push({
                id: String(item.id || ""), number: Number(item.number) || 0,
                title: String(item.title || ""),
                repository: String(item.repository_url || "").replace("https://api.github.com/repos/", ""),
                url: String(item.html_url || ""), updatedAt: String(item.updated_at || ""),
                user: String((item.user || {}).login || ""), draft: item.draft === true
            });
        }
        return reverseUpdated(result, "updatedAt");
    }

    function parsePullRequests(raw, data) {
        var value = JSON.parse(raw || "{}");
        var search = ((value.data || {}).search || {});
        var nodes = Array.isArray(search.nodes) ? search.nodes : [];
        var result = [];
        for (var index = 0; index < nodes.length; ++index) {
            var item = nodes[index] || {};
            if (item.number === undefined || item.number === null)
                continue;
            var repository = String((item.repository || {}).nameWithOwner || "");
            var commitNodes = (((item.commits || {}).nodes) || []);
            var rollup = commitNodes.length > 0 ? (((commitNodes[0].commit || {}).statusCheckRollup) || {}) : {};
            result.push({
                id: repository + "#" + item.number, number: Number(item.number), title: String(item.title || ""),
                repository: repository, url: String(item.url || ""), updatedAt: String(item.updatedAt || ""),
                draft: item.isDraft === true, checks: String(rollup.state || "NONE")
            });
        }
        data.myPullRequests = reverseUpdated(result, "updatedAt");
        data.myPullRequestsTotal = Number(search.issueCount) || result.length;
    }

    function parseRepositoryPage(raw, data) {
        var value = JSON.parse(raw || "{}");
        var graph = value.data || {};
        var viewer = graph.viewer || {};
        var connection = viewer.repositories || {};
        var nodes = Array.isArray(connection.nodes) ? connection.nodes : [];
        data.login = String(viewer.login || data.login || "");
        data.rateLimit = graph.rateLimit || data.rateLimit;
        for (var index = 0; index < nodes.length; ++index) {
            var item = nodes[index] || {};
            data.repositories.push({
                name: String(item.name || ""), nameWithOwner: String(item.nameWithOwner || ""),
                url: String(item.url || ""), archived: item.isArchived === true, fork: item.isFork === true,
                stars: Number(item.stargazerCount) || 0, issues: Number((item.issues || {}).totalCount) || 0,
                prs: Number((item.pullRequests || {}).totalCount) || 0, updatedAt: String(item.updatedAt || ""),
                activeActions: 0
            });
        }
        return connection.pageInfo || {};
    }

    function warn(job, label, message) {
        job.data.warnings.push(label + ": " + sanitizeError(message, "request failed"));
    }

    function baseFinished(job) {
        --job.basePending;
        maybeStartActions(job);
    }

    function maybeStartActions(job) {
        if (job !== _job || job.basePending !== 0 || !job.repositoriesDone)
            return;
        var filtered = [];
        for (var index = 0; index < job.data.repositories.length; ++index) {
            var repository = job.data.repositories[index];
            if ((!job.options.includeArchived && repository.archived) || (!job.options.includeForks && repository.fork))
                continue;
            filtered.push(repository);
        }
        job.data.repositories = filtered;
        if (job.options.actionScan === "off" || filtered.length === 0) {
            finishRefresh(job);
            return;
        }
        var repositories = filtered.slice();
        repositories.sort(function(left, right) { return String(right.updatedAt).localeCompare(String(left.updatedAt)); });
        if (job.options.actionScan === "recent")
            repositories = repositories.slice(0, job.options.actionRepoLimit);
        var cutoff = new Date(Date.now() - job.options.failedDays * 86400000);
        var cutoffDate = cutoff.toISOString().slice(0, 10);
        job.cutoffTime = cutoff.getTime();
        job.actionTasks = [];
        var statuses = ["in_progress", "queued", "waiting", "requested", "pending"];
        for (var repo = 0; repo < repositories.length; ++repo) {
            for (var status = 0; status < statuses.length; ++status)
                job.actionTasks.push({repository: repositories[repo].nameWithOwner, status: statuses[status], completed: false, cutoff: cutoffDate});
            job.actionTasks.push({repository: repositories[repo].nameWithOwner, status: "completed", completed: true, cutoff: cutoffDate});
        }
        job.actionNext = 0;
        job.actionActive = 0;
        pumpActions(job);
    }

    function pumpActions(job) {
        if (job !== _job)
            return;
        while (job.actionActive < job.options.actionConcurrency && job.actionNext < job.actionTasks.length) {
            var task = job.actionTasks[job.actionNext++];
            ++job.actionActive;
            var endpoint = "/repos/" + task.repository + "/actions/runs?status=" + task.status;
            if (task.completed)
                endpoint += "&created=%3E%3D" + task.cutoff;
            endpoint += "&per_page=100";
            fetchActionPage(job, task, endpoint, 1);
        }
    }

    function fetchActionPage(job, task, endpoint, page) {
        execute(["api", "-H", "Accept: application/vnd.github+json", endpoint + "&per_page=10&page=" + page], function(ok, stdout, error) {
            var count = 0;
            if (ok) {
                try {
                    var value = JSON.parse(stdout || "{}");
                    var rows = value.workflow_runs;
                    if (!Array.isArray(rows))
                        throw new Error("not an array");
                    count = rows.length;
                    root.collectActions(job, task, JSON.stringify([value]));
                } catch (_) {
                    root.warn(job, "actions " + task.repository, "invalid API response");
                    ok = false;
                }
            } else {
                root.warn(job, "actions " + task.repository, error);
            }
            if (ok && count === 10 && page < 100) {
                root.fetchActionPage(job, task, endpoint, page + 1);
                return;
            }
            if (ok && count === 10)
                root.warn(job, "actions " + task.repository, "pagination stopped at 100 pages");
            --job.actionActive;
            if (job.actionNext >= job.actionTasks.length && job.actionActive === 0)
                root.finishRefresh(job);
            else
                root.pumpActions(job);
        });
    }

    function collectActions(job, task, raw) {
        var incoming = flattenPages(raw, "workflow_runs");
        for (var index = 0; index < incoming.length; ++index) {
            var item = incoming[index] || {};
            var row = {
                id: item.id, repository: task.repository, name: String(item.name || item.display_title || "Workflow"),
                title: String(item.display_title || ""), status: String(item.status || ""),
                conclusion: String(item.conclusion || ""), event: String(item.event || ""),
                branch: String(item.head_branch || ""), url: String(item.html_url || ""),
                createdAt: String(item.created_at || ""), updatedAt: String(item.updated_at || "")
            };
            if (task.completed) {
                var failed = row.conclusion === "failure" || row.conclusion === "timed_out" || row.conclusion === "action_required" || row.conclusion === "startup_failure";
                if (failed && Date.parse(row.createdAt) >= job.cutoffTime)
                    job.failedById[String(row.id)] = row;
            } else if (row.status === "in_progress" || row.status === "queued" || row.status === "waiting" || row.status === "requested" || row.status === "pending") {
                job.actionsById[String(row.id)] = row;
            }
        }
    }

    function finishRefresh(job) {
        if (job !== _job)
            return;
        var key;
        for (key in job.actionsById)
            job.data.actions.push(job.actionsById[key]);
        for (key in job.failedById)
            job.data.failedActions.push(job.failedById[key]);
        job.data.actions = reverseUpdated(job.data.actions, "createdAt");
        job.data.failedActions = reverseUpdated(job.data.failedActions, "updatedAt").slice(0, job.options.failedLimit);
        var actionCounts = {};
        for (var action = 0; action < job.data.actions.length; ++action) {
            var repository = job.data.actions[action].repository;
            actionCounts[repository] = (actionCounts[repository] || 0) + 1;
        }
        for (var repo = 0; repo < job.data.repositories.length; ++repo)
            job.data.repositories[repo].activeActions = actionCounts[job.data.repositories[repo].nameWithOwner] || 0;
        if (job.repositoryFailed && job.data.repositories.length === 0) {
            job.data.state = "error";
            job.data.message = "GitHub repositories could not be loaded.";
        }
        if ((job.data.rateLimit && Number(job.data.rateLimit.remaining) <= 0) || job.data.warnings.join(" ").match(/rate.?limit|secondary rate/i)) {
            job.data.state = "rate-limited";
            job.data.message = "GitHub API rate limit reached.";
        }
        job.data.warnings = job.data.warnings.filter(function(value, index, values) { return values.indexOf(value) === index; });
        var callback = job.callback;
        _job = null;
        callback(job.data);
    }

    function fetchRepositoryPage(job, cursor) {
        var arguments = ["api", "graphql", "-f", "query=" + repositoryQuery(job.options.repositoryScope)];
        if (cursor)
            arguments.push("-F", "cursor=" + cursor);
        execute(arguments, function(ok, stdout, error) {
            if (!ok) {
                root.warn(job, "repositories", error);
                job.repositoryFailed = true;
                job.repositoriesDone = true;
                root.maybeStartActions(job);
                return;
            }
            try {
                var pageInfo = root.parseRepositoryPage(stdout, job.data);
                if (pageInfo.hasNextPage === true && /^[A-Za-z0-9_-]{1,256}$/.test(String(pageInfo.endCursor || ""))) {
                    root.fetchRepositoryPage(job, String(pageInfo.endCursor));
                    return;
                }
                if (pageInfo.hasNextPage === true)
                    root.warn(job, "repositories", "pagination cursor missing");
            } catch (_) {
                root.warn(job, "repositories", "invalid API response");
                job.repositoryFailed = true;
            }
            job.repositoriesDone = true;
            root.maybeStartActions(job);
        });
    }

    function refresh(options, callback) {
        if (_job !== null)
            return false;
        var job = {
            options: options, callback: callback, data: emptyData(options), basePending: 4,
            repositoriesDone: false, repositoryFailed: false, actionsById: {}, failedById: {}
        };
        _job = job;
        execute(["auth", "status", "--hostname", "github.com"], function(authenticated, stdout, error, exitCode) {
            if (!authenticated) {
                job.data.state = exitCode === 126 && error === "command-unavailable" ? "gh-not-installed" : "logged-out";
                job.data.message = job.data.state === "gh-not-installed" ? "GitHub CLI is not installed." : "Sign in with gh auth login to load GitHub data.";
                root._job = null;
                callback(job.data);
                return;
            }
            root.fetchRestPages(job, "notifications", "/notifications?all=false&participating=false", "", function(ok, rows, failure) {
                if (ok) try { job.data.notifications = root.parseNotifications(JSON.stringify([rows])); } catch (_) { root.warn(job, "notifications", "invalid API response"); }
                else root.warn(job, "notifications", failure);
                root.baseFinished(job);
            });
            var archive = options.includeArchivedReviews ? "" : "+archived%3Afalse";
            var draft = options.includeDraftReviews ? "" : "+draft%3Afalse";
            root.fetchRestPages(job, "review-requests", "/search/issues?q=is%3Aopen+is%3Apr+review-requested%3A%40me" + draft + archive, "items", function(ok, rows, failure) {
                if (ok) try { job.data.reviewRequests = root.parseSearch(JSON.stringify([{items: rows}])); } catch (_) { root.warn(job, "review-requests", "invalid API response"); }
                else root.warn(job, "review-requests", failure);
                root.baseFinished(job);
            });
            root.fetchRestPages(job, "assigned-issues", "/search/issues?q=is%3Aopen+is%3Aissue+assignee%3A%40me" + archive, "items", function(ok, rows, failure) {
                if (ok) try { job.data.assignedIssues = root.parseSearch(JSON.stringify([{items: rows}])); } catch (_) { root.warn(job, "assigned-issues", "invalid API response"); }
                else root.warn(job, "assigned-issues", failure);
                root.baseFinished(job);
            });
            var search = "is:open is:pr author:@me sort:updated-desc" + (options.includeArchived ? "" : " archived:false");
            root.execute(["api", "graphql", "-f", "query=" + root.pullRequestQuery, "-F", "search=" + search], function(ok, output, failure) {
                if (ok) try { root.parsePullRequests(output, job.data); } catch (_) { root.warn(job, "my-pull-requests", "invalid API response"); }
                else root.warn(job, "my-pull-requests", failure);
                root.baseFinished(job);
            });
            root.fetchRepositoryPage(job, "");
        });
        return true;
    }

    function markNotification(id, callback) {
        execute(["api", "--method", "PATCH", "/notifications/threads/" + id], function(ok, stdout, error) {
            callback(ok, ok ? "Notification marked read." : error);
        });
    }

    function markAll(boundary, ids, callback) {
        var before = new Date(Date.parse(boundary) - 1000).toISOString().replace(".000Z", "Z");
        execute(["api", "--method", "PUT", "/notifications", "-f", "last_read_at=" + before], function(ok, stdout, error) {
            if (!ok) {
                callback(false, error);
                return;
            }
            var next = function(index) {
                if (index >= ids.length) {
                    callback(true, "All displayed notifications marked read.");
                    return;
                }
                root.execute(["api", "--method", "PATCH", "/notifications/threads/" + ids[index]], function(patched, ignored, failure) {
                    if (patched)
                        next(index + 1);
                    else
                        callback(false, failure);
                });
            };
            next(0);
        });
    }
}
