# AI sessions (infra)

Local notes from AI sessions on this repository. Everything in this folder except this README is ignored by git.

Chats get long, get summarized or get deleted. A session file keeps the goal, the current state and every decision with its reason, so any new chat can pick up the task where the last one stopped. Projects created with `newproj-*` or `make ai-sessions` get their own `.ai-sessions/` from [devkit/templates/ai-sessions/README.md](../devkit/templates/ai-sessions/README.md); this one is the same idea for work on the infra repository itself.

## What is different here

- **These sessions run on the host.** The launchers refuse to start the jail inside this repository, so the AI tool that works here runs outside any container, with your user's access. That is one more reason to never put secrets in these files.
- **The devkit skills are not loaded automatically on the host.** To use them while working here: `claude --plugin-dir devkit`. The prompt below works without them.
- **Results depend on the machine.** Integration tests behave differently on Linux with SELinux enforcing, on GitHub's runners and on a Mac with a podman machine. Write down where each check ran.

## Naming

- **Id**: the ticket key (`ABC-123`), `GH-<number>` for a GitHub issue, or the start date (`2026-10-28`) when there is no ticket.
- **Short name**: a few lowercase words joined by hyphens (`jail-plugin-mount`).

```
.ai-sessions/
├── README.md                          # this file, the only one in git
├── 2026-10-28-devkit-skills.md        # the session file
├── 2026-10-28/                        # artefacts: test logs, podman inspect output, scratch scripts
└── handoff/
    └── 2026-10-28-devkit-skills.md
```

## Start a session

Paste this prompt at the start of the session and replace `<ID>` and `<short-name>`:

```text
We are working on the infra repository, task <ID> (<short-name>). Keep the session file at .ai-sessions/<ID>-<short-name>.md.

1. If the file exists, read all of it before doing anything else, and the handoff in .ai-sessions/handoff/ if there is one. Then tell me in a few lines what the goal is, where we stopped, and what the next step is. Check that state against the repository (branch, commits, uncommitted changes) and tell me if it differs.
2. If it does not exist, create it with these sections and fill in what you already know:

   # <ID>: <short-name>
   ## Goal
   ## Links
   (ticket, branch, PR, docs, upstream issues)
   ## Current state
   (what is done, what is not; for each check: the command, where it ran
   (Linux + SELinux, macOS + podman machine, CI) and the result)
   ## Next steps
   ## Open questions
   ## Decision log
   (newest last; never edit or delete earlier entries)

3. Keep the file up to date during the whole session, without me asking:
   - When we take a decision, append it to "Decision log" as
     "- YYYY-MM-DD: <decision>. Why: <reason>. Rejected: <alternatives, if any>."
     If a decision replaces an earlier one, add a new entry that says so; do not change the old one.
   - After each step that changes the state of the task (code written, tests run, PR opened, question answered), update "Current state", "Next steps" and "Open questions".
   - Before you end a turn where something changed, make sure the file reflects it.
4. Logs and scratch files go in .ai-sessions/<ID>/. Link them from "Current state".
5. Write facts, not summaries of the chat: file names, make targets, commands, results.
6. Never write secrets, tokens, passwords, registry credentials or personal data in these files.
```

## Continue in a new chat

Paste the same prompt with the same `<ID>` and `<short-name>`. The AI reads the file and continues from "Next steps".

## Handoff

When a chat is about to be compacted, or someone else will take over:

```text
Write a handoff for <ID> at .ai-sessions/handoff/<ID>-<short-name>.md, replacing the previous one. Sections:

# Handoff: <ID>: <short-name>
Last updated: YYYY-MM-DD.
## 1. The task
## 2. What we know
(facts about podman, SELinux, the podman machine, Claude Code and the tools involved, each with how it was verified and on which machine)
## 3. Done
(commits, files, test levels run and where)
## 4. Left to do
## 5. Traps
(what broke the jail, the volumes or the tests, and what not to try again)
## 6. How to check it
(make targets and commands, with the expected result on each platform)
```

## Tips

- One file per task. The decision log is the history: both the old and the new entry stay when a decision changes.
- Record which `make test-*` levels ran and where. "Tests pass" without the level and the machine is not a fact.
- Do not store secrets or personal data here.
