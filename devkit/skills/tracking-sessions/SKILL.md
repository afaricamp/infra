---
name: tracking-sessions
description: Keeps the task's session file in .ai-sessions/ (goal, links, current state, next steps, open questions and an append-only decision log) so work survives long, compacted or new chats. Resumes a task from its file, updates it as the work moves, stores manual-check artefacts next to it and writes handoffs. Use it when someone says to continue or resume a task or ticket, asks where we stopped, mentions .ai-sessions or the session file, asks to note or record a decision, or asks for a handoff or for context to carry into a new chat. Do not use it to start a new feature from a ticket (use starting-features).
---

# Tracking sessions

## Before you start

- Find `.ai-sessions/README.md` in the project root. It holds the naming, the sections of a session file and the handoff layout; this skill follows it. If the project has no `.ai-sessions/`, create it: copy `${CLAUDE_PLUGIN_ROOT}/templates/ai-sessions/README.md` to `.ai-sessions/README.md` and add these lines to `.gitignore` if they are missing:

  ```
  # Local AI session notes (see .ai-sessions/README.md)
  .ai-sessions/*
  !.ai-sessions/README.md
  ```

- Work out the task id, in this order: what the user said (`ABC-123`, `GH-42`), the ticket in the branch name (`feat/ABC-123-csv-export`), a session file whose short name matches the branch slug. If none of these settles it, list the session files and ask.
- Find the file: `ls .ai-sessions/<id>-*.md`. More than one match: ask which.

## Resume a task

```
- [ ] 1. Read the session file in full, and the handoff if there is one
- [ ] 2. Check it against the repository
- [ ] 3. Report and continue from "Next steps"
```

1. Read `.ai-sessions/<id>-<short-name>.md` and `.ai-sessions/handoff/<id>-<short-name>.md`. Read the artefacts in `.ai-sessions/<id>/` only when a step needs them.
2. Compare "Current state" with the repository: `git branch --show-current`, `git log --oneline -10`, `git status`, and the files it names. The file can be stale; the repository is the truth.
3. Tell the user, in a few lines: the goal, where the work stopped, the next step, open questions, and any difference you found in step 2. Then continue with the next step, unless it needs a decision from the user.

Do not redo work the file marks as done and checked. Do not reopen a decision from the log unless the user asks or a new fact contradicts its reason; then say so and record the new decision.

## Create a session file

Create `.ai-sessions/<id>-<short-name>.md` with the sections in the prompt of `.ai-sessions/README.md`, and fill in what you know: goal and acceptance criteria, links (ticket URL, branch, parent branch), and "Current state: nothing implemented".

## Keep it up to date

While the skill is active, without being asked:

- Append every decision to "Decision log" in the format the README gives: date, decision, why, rejected alternatives. Never edit or delete an earlier entry; a changed decision is a new entry that names the one it replaces.
- After each step that changes the state of the task (code written, tests run, PR opened, question answered), update "Current state", "Next steps" and "Open questions". For each check write the command and its result, not "tests pass".
- Before ending a turn in which something changed, make sure the file reflects it.
- Facts, not chat summaries: paths, commands, results, ticket and PR numbers.

## Artefacts

Files made to check the work by hand go in `.ai-sessions/<id>/`: `.http` requests with their `http-client.env.json` (and a `http-client.private.env.json` with local development credentials only), small scripts, sample payloads, command output worth keeping. Link each one from "Current state". Anything the project should keep (tests, the `.http` collection in `http/`, docs) goes in the repository instead.

## Write a handoff

When the user asks for one, or before a chat is compacted when they asked you to keep a handoff:

1. Bring the session file up to date first.
2. Write `.ai-sessions/handoff/<id>-<short-name>.md` with the sections the README gives, replacing the previous handoff. It must stand on its own: someone who never saw the chat or the session file can continue from it.
3. In "What we know", mark each fact as verified (and how: code read, query run, person asked) or not verified.
4. Report the path.

## Checks

- `git check-ignore -q .ai-sessions/<id>-<short-name>.md` succeeds: the notes are not going to be committed. If it fails, fix `.gitignore` before writing anything else.
- No secrets, tokens, passwords or personal data in any file under `.ai-sessions/`. AI tools read this folder and send it to their provider.

## Common mistakes

- Editing an old decision log entry instead of appending a new one.
- "Current state" that says what was planned instead of what was done and checked.
- Trusting a stale session file over the repository.
- A handoff that only makes sense with the chat next to it.
