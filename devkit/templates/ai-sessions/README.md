# AI sessions

Local notes from your AI sessions (Claude Code, Junie, Copilot…). Everything in this folder except this README is ignored by git, so the notes stay on your machine.

Chats get long, get summarized or get deleted. A session file keeps the goal, the current state and every decision with its reason, so any new chat can pick up the task where the last one stopped.

## Naming

Each task has an id and a short name:

- **Id**: the ticket key as the tracker writes it (`ABC-123`), `GH-<number>` for a GitHub issue, or the start date (`2026-10-28`) when there is no ticket.
- **Short name**: a few lowercase words joined by hyphens (`csv-export`), usually the slug of the branch.

Everything for one task uses `<id>-<short-name>`:

```
.ai-sessions/
├── README.md                     # this file, the only one in git
├── ABC-123-csv-export.md         # the session file
├── ABC-123/                      # artefacts: .http requests, scripts, sample data, output
└── handoff/
    └── ABC-123-csv-export.md     # handoff for a new chat or another person
```

## Start a session

With the devkit plugin, `/devkit:starting-features <ticket or description>` creates the session file, and `devkit:tracking-sessions` keeps it up to date, resumes it and writes handoffs. With any other tool, paste this prompt at the start of the session and replace `<ID>` and `<short-name>`:

```text
We are working on <ID> (<short-name>). Keep the session file at .ai-sessions/<ID>-<short-name>.md.

1. If the file exists, read all of it before doing anything else, and the handoff in .ai-sessions/handoff/ if there is one. Then tell me in a few lines what the goal is, where we stopped, and what the next step is. Check that state against the repository (branch, commits, files) and tell me if it differs.
2. If it does not exist, create it with these sections and fill in what you already know:

   # <ID>: <short-name>
   ## Goal
   (what changes for whom, and the acceptance criteria)
   ## Links
   (ticket, branch, parent branch, PR, docs, chat threads)
   ## Current state
   (what is done, what is not, what was checked and how)
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
4. Files you create to check the work by hand (requests, scripts, sample data, output) go in .ai-sessions/<ID>/. Link them from "Current state".
5. Write facts, not summaries of the chat: file names, commands, results, ticket numbers.
6. Never write secrets, tokens, passwords or personal data in these files.
```

## Continue in a new chat

Paste the same prompt with the same `<ID>` and `<short-name>`, or with devkit say "continue with <ID>". Claude reads the file and continues from "Next steps".

## Handoff

When a chat is about to be compacted, or someone else will take over, ask for a handoff ("write a handoff for <ID>"). The session file is the running log; the handoff is a briefing that someone with no context can read on its own. It goes in `handoff/<ID>-<short-name>.md`:

```text
Write a handoff for <ID> at .ai-sessions/handoff/<ID>-<short-name>.md, replacing the previous one. Sections:

# Handoff: <ID>: <short-name>
Last updated: YYYY-MM-DD.
## 1. The task
(the original request and acceptance criteria, in full)
## 2. What we know
(facts about the code and the systems that matter for this task, each with how it was verified; mark what is not verified)
## 3. Done
(commits, files, checks run and their results)
## 4. Left to do
(in order, with the files involved)
## 5. Traps
(what went wrong or almost did, and what not to try again)
## 6. How to check it
(commands, requests in .ai-sessions/<ID>/, expected results)
```

## Tips

- One file per task. If a task splits into stacked branches, keep one session file and list every branch under "Links".
- The decision log is the history. If something was decided and later changed, both entries stay.
- `.http` files in `<ID>/` may use an `http-client.private.env.json` with local development credentials. Never production ones.
- Do not store secrets or personal data here. The folder is not committed, but AI tools read it and send it to their provider.
- Delete old sessions when you no longer need them; nothing else depends on them.
