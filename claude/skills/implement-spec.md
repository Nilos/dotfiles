---
name: implement-spec
description: End-to-end workflow to pick up and implement a spec — a ticket (Jira, Linear, GitHub issue, etc.), a markdown/design doc, a URL, or pasted requirements. Gathers context, asks clarifying questions, explores the codebase, decides on a feature flag, checks out a branch, and implements without committing. Use when asked to "implement this spec", "pick up this ticket", "start work on X", "let's build this", or similar.
---

# Implement a Spec

A structured pickup-to-implementation flow for a single spec in the current
repo. The spec can come from any source: an issue tracker ticket, a local
file, a URL, or text pasted into the conversation. Track progress through the
steps below with a todo list so nothing gets skipped. Do **not** commit at
the end — the user commits their own work; never assume git actions are
pre-approved.

## Step 0 — Get the spec

Use whatever the user already provided in their invocation:

- **Pasted text** — use it as-is.
- **File path** — read it.
- **URL or tracker reference** (e.g. `PROJ-1234`, `#123`, a Jira/Linear/GitHub
  link) — fetch it with whatever tool is available: an MCP server for that
  tracker, `gh issue view` for GitHub, WebFetch for a public URL. If no tool
  can reach it, say so and ask the user to paste the content.
- **Nothing** — ask:

> What should I implement? (paste the spec, give a file path, or a ticket
> key/URL)

Also note an identifier for the work if one exists (ticket key, issue
number); it's used for flag and branch names below. If there's none, derive a
short kebab-case slug from the spec title.

## Step 1 — Gather context

Read the spec fully: goal, acceptance criteria, constraints, comments, and any
mention of rollout or a feature flag. Then follow links to related context —
a parent epic/story, linked design docs, referenced issues or PRs — since
these often carry broader goals or cross-cutting constraints (e.g. "everything
in this epic ships behind one umbrella flag") that the spec itself doesn't
repeat. Don't skip this even if the spec looks self-contained.

## Step 2 — Clarify and explore

These two happen together, not sequentially — exploration usually surfaces
the questions worth asking, and answers usually point at where to look next.

- Identify which part(s) of the codebase the spec touches (check
  `AGENTS.md`/`CLAUDE.md`/README for a map of services or modules). If
  unclear from the spec, that's itself worth exploring/asking about.
- Do a quick, targeted exploration (use the `Explore` agent for anything
  beyond a couple of greps) to sanity-check feasibility and spot anything the
  spec leaves ambiguous: which endpoint/class/table is actually involved,
  whether existing code already does something close, naming conventions to
  follow, existing feature-flag patterns.
- If the spec touches code outside this repo (infra, shared libraries,
  sibling repos), look there too rather than assuming it's out of scope.
- Ask the user clarifying questions (via AskUserQuestion when there's a
  genuine decision, plain text when it's a quick check) for anything still
  unclear after exploring — don't guess on ambiguous requirements, and don't
  ask about things the code already answered.
- Check whether this work is already in flight: sibling git worktrees, or
  local/remote branches matching the identifier. If you find one, tell the
  user and ask whether to continue there instead of starting fresh.

## Step 3 — Decide: feature flag?

Default toward **using a feature flag** if the repo has a flagging system,
unless the change is trivial, purely internal (no behavior change reachable by
an external actor), or a straight bugfix with no rollout risk. If the spec
already states a flag is needed, treat that as settled — otherwise make the
call yourself from the spec + context + exploration, and say which way you
leaned and why. If the repo has no flagging system, skip this step and the
next.

If a flag is needed, derive its name from the identifier and slug, following
the convention of existing flags in the repo (check the relevant service's
flag/`Features` file for exact casing and whether names are inline string
literals or constants) — e.g. `PROJ-1234-shadow-validation-rate`. Propose the
name to the user rather than silently deciding.

## Step 4 — Ask the user to create the flag

Unless a flag-management tool is available in this environment, the flag
can't be created programmatically. Give the user the exact name from Step 3
and a one-line description of what it gates, and wait for their confirmation
before wiring flag checks into code that reads it.

## Step 5 — Branch

Check `git status` first — if there are uncommitted changes on the current
branch that aren't yours to discard, stash or ask before switching.

Check out a new branch from an up-to-date default branch, following the
branch naming convention already used in the repo (look at recent branches
and worktrees). If none is evident, use `<identifier>-<slug>` in lowercase.

## Step 6 — Implement

Implement the spec. Follow the repo's own conventions (`AGENTS.md`,
`CLAUDE.md`, linters, generators). Keep comments minimal — one-liners at
most; rationale belongs in the eventual PR description, not the diff.

**Do not commit.** The user commits their own work. If the diff grows large
enough that it's no longer one coherent change, stop and ask the user whether
to:

- make a partial commit now and keep going, or
- split the remaining work into a separate follow-up.

Don't make that call unilaterally — it affects how they'll want to review and
ship the work.
