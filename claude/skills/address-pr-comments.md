---
name: address-pr-comments
description: Address review comments on the current branch's GitHub PR — fix the code, reply to each thread prefixed with "[Claude-Bot]", commit per logical fix, then push. Use when asked to "address PR comments", "respond to review feedback", "handle the comments on this PR", or similar, for the PR belonging to the current branch.
---

# Address PR Comments

Fix reviewer feedback on the current branch's PR end to end: read every open
thread, fix or explain, reply, commit, validate, and push — without the user
having to relay each comment by hand.

## Decided conventions (don't re-ask the user for these)

- **Scope:** unresolved inline review comments **and** general PR conversation
  (issue) comments. Resolved review threads are left alone.
- **Bot comments count too** (CodeRabbit, Dependabot, etc.) — treated the same
  as human reviewer comments.
- **Idempotency:** a thread/comment whose latest entry is already a
  `[Claude-Bot]` reply is treated as handled and skipped, unless a human
  posted something new after that reply.
- **Ambiguous or disagreeable comments:** never silently drop them. Skip the
  code change but still post a `[Claude-Bot]` reply explaining the reasoning.
- **Opt-out authors:** GitHub usernames listed in
  `address-pr-comments-no-ai-contacts.yml` (next to this file) never get a
  `[Claude-Bot]` reply. Their comments are still
  read, fixed, and committed like any other — only Step 6 changes: the
  drafted reply is printed in chat instead of posted, so the user can send it
  themselves. Add a username there whenever someone asks not to be replied to
  by the bot.
- **Never mark threads resolved** — that's left for the human reviewer to do.
- **Never force-push.** If `git push` is rejected as non-fast-forward, stop
  and ask the user how to proceed instead of rebasing or force-pushing.
- Follow the current repo's own engineering conventions for every fix
  (CLAUDE.md, linters, code generators, etc.) — this is not a special bot
  code path that gets to skip normal quality bars.

## Step 1 — Find the PR

```bash
gh pr view --json number,url,headRefName,baseRefName,state,isDraft
```

- No PR for the current branch, or it's closed/merged → stop and tell the user.
- Check if the branch is pancake-tracked (your org's stacked-diffs tool, if
  present): `command -v pk` and `pk log`. Remember the result — it changes
  how you push in Step 8. If `pk` isn't installed/relevant, ignore this.

## Step 2 — Fetch comments

Get the owner/repo once (`gh repo view --json owner,name`), then pull both
comment sources for the PR number from Step 1.

**Inline review threads** (GraphQL — this is the only way to get
`isResolved` and the full thread history in one call):

```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            path
            line
            comments(first: 50) {
              nodes { databaseId author { login } body createdAt }
            }
          }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F pr=<number>
```

**General PR conversation comments:**

```bash
gh api repos/<owner>/<repo>/issues/<pr>/comments
```

**Opt-out list:** also read `address-pr-comments-no-ai-contacts.yml` next to
this skill file (a YAML list under `usernames:`). Treat a missing file as an
empty list. Keep
this list in memory for Step 6 — matching is case-insensitive.

## Step 3 — Filter to what actually needs action

- Drop any review thread where `isResolved` is true.
- Drop any thread/comment whose last entry is a `[Claude-Bot]`-prefixed body
  with no newer human comment after it.
- Everything else stays in scope, including pure questions/nits — they still
  need a reply even if no code changes.

## Step 4 — Understand and group the work

For each remaining thread/comment, read the surrounding code at `path`/`line`
(or `gh pr diff <number>` for full context) to classify it:

- an actionable change request,
- a question or nit with no code change needed, or
- something you disagree with or find ambiguous.

Group comments that belong to the same logical fix (same file, same rename
applied in multiple places, same pattern) so they land in **one** commit.
Keep unrelated fixes in separate commits — don't bundle just to reduce commit
count.

## Step 5 — Apply fixes, per group

1. Make the code change using the repo's normal conventions.
2. For pure questions/nits, or comments you disagree with/are unsure about:
   make no code change, but prepare an explanatory reply (Step 6).
3. Commit using this repo's own commit convention (check `CLAUDE.md` first;
   fall back to Conventional Commits `<type>(<scope>): <description>` if
   nothing is documented) — imperative, lowercase, no trailing period,
   ≤72 chars. Describe the actual fix, not "address PR comments", e.g.
   `fix(application-form): guard against undefined job id`.

## Step 6 — Reply to every thread/comment in scope

**Opt-out check first:** for each thread/comment, check the *original*
author (not necessarily the person who wrote the latest message) against
the `address-pr-comments-no-ai-contacts.yml` list from Step 2. If they're on it:

- Do **not** call the GitHub API for this thread/comment — no `[Claude-Bot]`
  reply gets posted, and no other comment mutation happens either.
- Draft the reply exactly as you would otherwise (same fixed/skipped wording
  from below, minus the `[Claude-Bot]` prefix), and print it in chat instead,
  labeled with the author's username and a link to the thread/comment, so the
  user can send it themselves in their own words or copy it as-is.
- The code fix and commit from Step 5 still happen normally — only the reply
  channel changes.

Everyone else follows the normal path below.

**Inline review comment** — reply in-thread using the top comment's
`databaseId` from Step 2:

```bash
gh api repos/<owner>/<repo>/pulls/<pr>/comments/<comment_id>/replies -f body="[Claude-Bot] <message>"
```

**General PR comment** — issue comments don't thread, so post a new comment
that references the original:

```bash
gh api repos/<owner>/<repo>/issues/<pr>/comments -f body="[Claude-Bot] <message>"
```

Every reply explains the *what/why*, not just "done":

- Fixed: `[Claude-Bot] Good catch — this threw on a missing job id; added a
  guard and a test. Fixed in <short-sha> .` (fill in `<short-sha>` after the
  commit from Step 5 exists and make sure there is a space after it)
- Skipped: `[Claude-Bot] Left as-is — <concrete reasoning>.`

Never leave a comment in scope without a reply, even if the outcome is "no
change made."

## Step 7 — Validate before pushing

Run this repo's normal static checks on the touched code before pushing —
don't push unvalidated fixes. Figure out the right command from the repo
itself (check `CLAUDE.md`/`package.json` scripts first):

- Nx monorepo: `pnpm nx affected --target=lint,type-check,test --base=<baseRefName> --silent`
- Otherwise: whatever the repo defines for lint/type-check/test (e.g.
  `npm test`, `make check`).

If checks fail: **do not push**. Report the failing project(s)/tests and the
error to the user and stop; fix or get direction before retrying.

## Step 8 — Push

- **Pancake-tracked branch:** `pk submit` (no `--publish` — this only updates
  the existing PR, it never re-drafts or republishes).
- **Plain branch:** `git push`.
- If the push is rejected as non-fast-forward, **stop** — never force-push
  (not even `--force-with-lease`). Tell the user the remote has diverged and
  ask how they want to proceed.

## Step 9 — Summarize

Report back: how many comments were fixed vs. skipped (with a one-line reason
per skip), the commit(s) created, whether the push succeeded, and the PR URL.
If any authors were on the opt-out list, call those out as a separate
"needs your manual reply" section with their drafted replies (already
printed in Step 6) so the user doesn't miss them.

## Rules

- Never resolve GitHub review threads — replying is the only mutation to
  thread state this skill performs.
- Never post a `[Claude-Bot]` reply (or any GitHub comment) to an author
  listed in `address-pr-comments-no-ai-contacts.yml` — hand the drafted reply
  to the user in chat instead.
- Never force-push.
- Never skip a comment silently.
- Never combine unrelated fixes into one commit.
- Static checks are a hard gate before push, not a suggestion.
