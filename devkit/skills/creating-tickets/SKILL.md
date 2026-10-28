---
name: creating-tickets
description: Drafts a ticket (Jira issue or GitHub issue) with context, acceptance criteria someone can check, links and blockers, checks for duplicates, and creates it only after the user approves the draft. Run it with /devkit:creating-tickets and a description, a Slack thread link or pasted notes.
disable-model-invocation: true
argument-hint: "<what the ticket is about, a Slack link or notes>"
---

# Creating tickets

## Before you start

- Where it goes: a Jira project (needs the Atlassian connector and a project key) or the repository's GitHub issues (needs `gh`). Ask if it is not clear. Without either, write the draft and tell the user to create it by hand.
- You need four things: what has to change, why and for whom, when it counts as done, and who to ask. If the request does not answer them, ask before drafting. Do not invent acceptance criteria.
- For a Slack link, read the thread with the Slack connector. Put the link and a summary in the ticket. Do not copy messages verbatim and leave out personal data about users.

## Steps

```
- [ ] 1. Check for duplicates
- [ ] 2. Pick type, labels and parent
- [ ] 3. Write the draft
- [ ] 4. Show it and wait for approval
- [ ] 5. Create it and report the link
```

### 1. Check for duplicates

Jira: JQL `project = <KEY> AND statusCategory != Done AND text ~ "<keywords>"`. GitHub: `gh issue list --state open --search "<keywords>"`. If one matches, show it and ask whether to create a new ticket or update that one.

### 2. Type, labels and parent

- Type: `Bug` for an error in existing behaviour, `Task` or `Story` for the rest, following what the project uses.
- Labels and epic or milestone: look at recent tickets in the same project and reuse their labels. Propose an epic only from the open ones; never invent a label the project does not use.

### 3. Write the draft

Summary: one imperative sentence that names the change ("Return 404 instead of 500 for unknown export IDs"), without type or labels.

Description, in the language the project's tickets use, written with the `devkit:writing-naturally` skill:

```markdown
<One or two paragraphs: what is needed, for whom and why. Real endpoint, component and service names.>

**Blocked by:** <ticket>

### Acceptance criteria

- <Observable result: "GET /exports/{id} returns 404 with a problem+json body for an unknown id">
- <What must not change>
- <Tests, docs, migration, when they apply>

### Links

- <Slack thread, design, incident, docs>

### Contacts

- <Name> (<team or role>)
```

Leave out sections with nothing to put in them. Each criterion is something a reviewer can check. Do not prescribe the implementation beyond what the request decides.

For a bug, add steps to reproduce, expected and actual behaviour, and the environment.

### 4. Show it and wait

Show the full draft with project, type, labels and parent. Point out open questions. Create nothing until the user approves.

### 5. Create and report

Create it (Atlassian connector, or `gh issue create --title … --body-file … --label …`). Report the key or number and the link. The user can then run `/devkit:starting-features <key>`.

## Common mistakes

- Acceptance criteria that cannot be checked ("works well", "is fast").
- Creating the ticket before the user saw the draft.
- Copying a Slack thread into the description.
