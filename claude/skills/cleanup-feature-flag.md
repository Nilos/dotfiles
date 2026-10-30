---
name: cleanup-feature-flag
description: Retire a fully-rolled-out (or permanently killed) feature flag — hardcode the check to the winning value, delete the dead branch and every file that only served it, update tests and flag mocks, verify build/lint/type-check/tests, then commit and open a draft PR. Works with any flag provider (LaunchDarkly, Split/Harness, Optimizely, AWS AppConfig, Unleash, Flagsmith, in-house, ...). Use when asked to "remove flag X", "clean up feature flag X", "retire flag X", "flag has been at 100% for a while, clean it up", or similar.
---

# Cleanup Feature Flag

A structured flow for retiring one feature flag end-to-end: find usages →
hardcode → delete dead code → fix tests → verify → branch/commit/PR. Track
progress with a todo list — this touches several files across a codebase
and it's easy to stop half done.

This skill covers **both directions**: a flag rolled out to 100% (keep the
"on" path, delete the "off" branch) and a flag killed/rolled back to 0%
(keep the "off" path, delete the "on" branch). For multivariate flags
(string/number/JSON variations), "direction" means **which variation won**.

## Step 0 — Confirm scope

Before touching anything, make sure you know:

1. **The exact flag key.** Copy it exactly as it's defined in the provider
   or code, don't paraphrase. Note any constant/enum name it's wrapped in
   too.
2. **Which direction / winning variation.** Which path stays. Look up the
   actual rollout status rather than trusting memory or phrasing:
   - **Provider MCP available** (a connected MCP server for the flag
     provider, e.g. LaunchDarkly, Split/Harness, Optimizely, AppConfig):
     fetch the flag and check, **per environment**, whether it's enabled,
     its targeting rules/segments, percentage rollouts, and which
     variation is served. Also check when it last changed if the provider
     exposes that.
   - **No provider MCP**: ask the user to export the flag's current state
     from the provider (UI export, CLI, or API) into a file and give you
     the path. Then:
     - Check the file is **less than 24 hours old** — use the export
       timestamp in the file's content if it has one, otherwise the file's
       modification time (`stat`). If it's older, or you can't tell, ask
       for a fresh export instead of using it.
     - Read the same per-environment details from it as above.
     - Don't commit the export file; it's a one-off input.

     Don't fall back to flag config, IaC, or defaults checked into the
     repo — they can lag behind what's actually live in the provider.

   The flag is only safe to clean up if **every** environment (production
   included) serves the same variation to everyone — no remaining
   targeting rules, segments, or partial percentages. If environments
   disagree, a rule still targets some users, or the result contradicts
   what the user asked for ("remove it, it's at 100%" but prod is at 50%),
   stop and show the user what you found before going further.

Don't proceed past this step on a guess — a wrong direction means deleting
the code that was supposed to stay. Report the rollout status you found
(and its source) to the user and get confirmation of the direction.

## Step 1 — Learn how this repo reads flags

Before grepping, figure out the repo's flag plumbing — it decides where to
look. Check CLAUDE.md / project rules / docs first, then look for:

- **The access layer**: SDK client calls, a wrapper service/hook/helper,
  decorators, middleware, or a config object loaded at startup. There may
  be more than one (e.g. a client-side hook and a server-side service).
- **Flag registries**: constants/enums of flag keys, typed flag
  definitions, generated type files (if generated, don't hand-edit — find
  the source and regenerate).
- **Non-code definitions**: provider config files (JSON/YAML, e.g. an
  AppConfig profile), infrastructure-as-code (e.g. Terraform resources for
  the flag), environment variables, CI config.
- **Mocks and defaults**: local-dev/test treatment tables, fallback
  default values, test helpers that force a flag on/off.

## Step 2 — Find every usage

Grep the literal flag key **and** any constant/enum name that wraps it
across the whole repo (not just the app you expect it in — flags leak into
shared libs, API mocks, fixtures, and test helpers):

```bash
git grep -n '<exact-flag-key>'
git grep -n '<FLAG_CONSTANT_NAME>'
```

Watch for keys that grep won't find literally: keys built by string
concatenation/templating, prefixed per environment, or converted between
cases (`my-flag` vs `MY_FLAG` vs `myFlag`). If the repo does that, search
for the variants too.

For anything beyond a handful of hits, delegate to the `Explore` agent (or
`general-purpose` for a very thorough sweep) and ask it to report, for
**each** usage site:

- File:line and the full surrounding conditional (not just the flag check
  line — the whole `if`/ternary/switch/branch it gates).
- Whether it gates a whole module/component/file or just a small block.
- **Every file that only exists to serve the branch you're about to
  delete** — this is the step most likely to be incomplete on a first
  pass, see Step 4.
- Whether the flag appears in registries, config/IaC, mock treatments, or
  test helpers.

## Step 3 — Hardcode the check

Replace the flag read with the winning value. Don't leave
`const isEnabled = true;` sitting next to the old call as a fossil — inline
the value into the conditional directly, or remove the conditional
entirely if it always resolves the same way:

```
// Before
enabled = flags.isEnabled("new-checkout", user)
if enabled and cart.hasItems():
    renderNewCheckout()
else:
    renderOldCheckout()

// After (flag is 100% on)
if cart.hasItems():
    renderNewCheckout()
```

Also remove now-unneeded plumbing around the check: loading/ready states
that only waited for the flag to resolve, user/context arguments fetched
only to evaluate it, and the flag's entry in any registry.

If the surrounding code evaluated **other**, unrelated flags too, check
whether *those* only existed to feed the branch you're deleting — see
Step 4, this cascades further than the flag itself.

## Step 4 — Trace the dead-code cascade, carefully

This is the step most likely to go wrong. Once a branch is unreachable,
everything that *only* served that branch is dead: modules, components,
helpers, styles, routes, "old" vs "new" implementation pairs. But
**cascades don't stop at one hop**, and **shared files are the trap**:

1. For every file the dead branch imports, check **all** of its importers
   across the repo, not just the one you already know about. A helper, a
   stylesheet, or a shared subview is often reused by the *surviving*
   branch too, even though it was originally written for the branch
   you're removing.
2. Do this for **every** file before deleting **any** of them — don't
   delete-as-you-go, because an earlier deletion can make a later file's
   "is this dead" check give a false answer.
3. Wrongly deleting a shared file often fails at **build time** (missing
   module/import), not in tests — the test suite can go green while the
   app is actually broken. Always run a real build (Step 6) before
   considering the cleanup done.
4. If a surviving shared file is named after the deleted owner, rename it
   to reflect its real owner — don't leave a confusingly-named survivor.
5. Parameters/props that were only threaded through to feed the dead
   branch (tracking IDs, other flag values passed down for the old path)
   become dead too, sometimes several call levels up. Trace them all the
   way to their source.

When in doubt about whether something is truly dead, grep for its name and
import path across the **whole repo**, not just the directory you're
working in.

## Step 5 — Fix tests and mocks

- Delete tests for deleted code.
- Remove the flag from mock treatment tables, fixtures, and test helpers
  that force it on/off.
- Rewrite tests that exercised the flag-gated branching: an on/off pair of
  cases usually collapses into a single test of the now-unconditional
  behavior — delete the gating tests, keep the behavioral assertions for
  the surviving path.
- Remove test stubs/mocks for anything deleted in Step 4.
- If deleting tests removes coverage for logic that still lives elsewhere,
  verify that logic still has *some* coverage before deleting — don't
  create a silent coverage gap. Say so explicitly if you can't find one.
- Large, mechanical test-file rewrites are a good candidate to delegate to
  a background `general-purpose` agent — give it the exact before/after
  shape of the source (don't make it re-derive that), a specific list of
  tests to remove/rewrite, and have it iterate to green itself before
  reporting back.

## Step 6 — Verify for real

Don't stop at tests. Flag cleanup regularly breaks compilation in ways
tests don't catch (see Step 4.3). Use the repo's own commands (check
CLAUDE.md, package scripts, Makefile, CI config) for:

- tests
- lint
- type-check (if the language has one)
- a real build

All must pass. If coverage thresholds are enforced, confirm the run still
clears them — deleting code can shift the ratio either way.

## Step 7 — Branch, commit, PR

1. Check out a new branch named per the repo's convention (see recent
   `git log`, CLAUDE.md, contributing docs) — don't rely on whatever branch
   the user happened to be on.
2. Commit using the repo's commit message convention. A flag removal is
   usually a chore/cleanup-type change.
3. Push and open a **draft** PR with a summary of what was hardcoded and
   what was deleted, plus the verification steps from Step 6 as a
   checklist.
4. Remind the user to archive/delete the flag **in the provider** once the
   PR is deployed everywhere — don't do it yourself. Removing it before
   every running version stops reading it makes those versions fall back
   to their default value.
5. If a problem surfaces *after* the PR is already up, fix it as a **new**
   commit on the same branch rather than rewriting history the user may
   already be reviewing — amending is fine only if that commit hasn't been
   pushed yet.

## Anti-patterns to avoid

- Deleting a file because it's "only used by the code I'm removing"
  without actually checking *all* its importers first — the exact mistake
  this skill exists to prevent.
- Trusting the test suite alone as proof the cleanup is safe — always run
  a real build too.
- Picking the direction from the user's phrasing or the code's default
  value without checking the real rollout status in the provider (or a
  fresh export from it).
- Leaving a hardcoded `flagIsOn = true` fossil instead of actually removing
  the conditional.
- Grepping only the literal key and missing usages via constants, enums,
  case variants, or config/IaC files.
- Batching multiple unrelated flags into one PR without the user asking —
  keep each flag's removal independently reviewable unless told otherwise.
- Silently dropping test coverage for logic that's still used elsewhere
  instead of confirming a replacement test exists.
