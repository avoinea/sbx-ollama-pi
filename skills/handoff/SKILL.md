---
name: handoff
description: Compact the current conversation into a structured handoff folder so a fresh agent can continue the work. Creates docs/<session-slug>/ with README, DECISIONS, PLAN, REPORT, TODO and HANDOFF docs. Use when the user asks for a handoff, invokes /handoff, or asks to summarize the session, write session documentation, or prepare context for the next session/agent.
argument-hint: "What will the next session be used for?"
---

# Handoff

Create `docs/<session-slug>/` in the current project and write the session docs there. Write in the user's language.

- `<session-slug>`: short kebab-case topic, e.g. `gpt6-luna-migration`. Prefix with `YYYY-MM-DD-` only to disambiguate repeated sessions. If the user named a target, use it.
- If the folder exists, read the files first and update/merge; never clobber.
- Create or update `./docs/handoff-next.md` pointing to the last session handoff.

## Always create

| File | Content |
|---|---|
| `README.md` | Index of the folder, one-line status, key facts, links to the other files |
| `DECISIONS.md` | Each decision taken, in order: decision, choice, why; include rejected alternatives and explicit user overrides |
| `PLAN.md` | Phases with status (done / pending / blocked) plus the operational details needed to continue |
| `REPORT.md` | Results, metrics, verification evidence; link to raw artifacts instead of copying them |
| `TODO.md` | Open items with owner; separate "closed" section |
| `HANDOFF.md` | For the next agent: current state, next steps, environment gotchas, suggested skills |

Add other files only when they carry weight, e.g. `ROLLBACK.md` for a revert procedure.

## Rules

- Reference, don't duplicate: commits/diffs, PRDs, issues, plans, external reports — cite path, commit hash, or URL.
- Never include secrets or keys; grep the folder for `sk-`, tokens, passwords before finishing.
- Keep files short: the folder is an index for a fresh agent, not a transcript.
- Tailor `HANDOFF.md` and `TODO.md` to the focus given in the argument.
- Commit and push the folder unless the user says otherwise or it is git-ignored; report path and commit hash.
- If the project root is a webroot, protect the folder from web access (e.g. deny-all `.htaccess`) and verify it after deploy.

## HANDOFF.md must cover

- Current state in 2-3 lines, plus commit/branch.
- What the next session should do first.
- Environment gotchas: missing tooling, timezones, ignored directories, deploy mechanics.
- Skills to use next, only if genuinely useful.
