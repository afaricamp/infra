---
name: committing-changes
description: Commits the working tree changes as Conventional Commits, pushes the branch and opens a draft PR, stacked on a parent branch when the work builds on one. Shows the plan and waits for confirmation before pushing. Run it with /devkit:committing-changes.
disable-model-invocation: true
argument-hint: "[parent branch to stack on]"
---

# Committing changes

## Before you start

- Run `git status`, `git diff`, `git diff --staged` and `git log --oneline origin/<default>..HEAD` to see what changed and what is already committed. Find the default branch with `git symbolic-ref --short refs/remotes/origin/HEAD`.
- Check the project's rules: `CONTRIBUTING.md`, a commitlint config, a PR template (`.github/pull_request_template.md`), `release-please` or `semantic-release` config. They win over the defaults below.
- Ticket: take it from the branch name (`feat/ABC-123-…` gives `ABC-123`). If the project's commits or PR titles carry tickets (`git log --oneline -20`) and the branch has none, ask for it. Never make one up.

## Steps

```
- [ ] 1. Check that it builds and the tests pass
- [ ] 2. Group the changes into commits
- [ ] 3. Commit
- [ ] 4. Work out the PR base
- [ ] 5. Show the push and PR plan and wait for confirmation
- [ ] 6. Push and open the draft PR
- [ ] 7. Update the session file
```

### 1. Check

Run the project's lint and test commands for the files that changed. If something fails, stop and report it; do not commit around it.

Check the diff for things that must not be committed: `.env` files, keys, tokens, credentials, debug output, large generated files, anything under `.ai-sessions/` other than its README. Stop and ask if you find one.

### 2. Group the changes

One commit per independent change. Code, its tests and the docs that describe it go together. An unrelated fix, a refactor or a dependency bump is its own commit. Stage by file or by hunk (`git add -p` is interactive and not available: use `git add <file>` or write a patch and `git apply --cached`).

### 3. Commit

Format: [Conventional Commits](https://www.conventionalcommits.org/).

```
<type>(<optional scope>): <summary in the imperative, lowercase, no period>

<body: why, when it is not obvious from the summary. Wrap at 72.>

Refs: ABC-123
BREAKING CHANGE: <what breaks and how to migrate, only when it does>
```

- Types: `feat` new behaviour, `fix` bug fix, `docs`, `refactor` (no behaviour change), `perf`, `test`, `build` (build system, dependencies), `ci`, `chore` (anything else that ships nothing).
- Release tools read the type: `feat` is a minor release, `fix` a patch, and an exclamation mark after the type (`feat!:`) or a `BREAKING CHANGE:` footer a major one. Pick the type for the effect on users, not for the size of the diff.
- Summary under 72 characters. If the project puts the ticket in the summary (`feat: add csv export (ABC-123)`), do that instead of the `Refs:` trailer.
- Add the attribution trailer the session asks for, if any.

### 4. Work out the PR base

- The default branch, unless the user names a parent branch or the branch was created from another feature branch (`git log --oneline --graph origin/<default>..HEAD` shows its commits).
- For a stacked PR the base is the parent branch. Check it is pushed (`git ls-remote --heads origin <parent>`) and has a PR (`gh pr list --head <parent> --state open`). If not, say so: the parent goes first.

### 5. Show the plan and wait

Show the commits, the push command and the full `gh pr create` command, then ask for confirmation. Push only after the user says yes.

- Title: the same format as a commit. With squash merge the title becomes the commit on the default branch, so use the type of the most significant change (`feat` over `fix` over the rest).
- Body: fill the project's PR template if there is one. Otherwise: what changed and why in a few plain sentences, how it was tested, and anything a reviewer should look at first. For a stacked PR, start with `Depends on #<parent PR>.` No summary of the diff file by file. Write the title, the body and any commit body with the `devkit:writing-naturally` skill.
- Always `--draft`.

### 6. Push and open the draft PR

```bash
git push -u origin <branch>
gh pr create --draft --base <base> --title "<title>" --body-file <file>
```

Inside the Claude jail `.git/config` is read-only, so `-u` fails, and there are usually no credentials for the remote or for `gh`. If the push or `gh` fails for either reason, do not retry other ways: print the two commands for the user to run on the host.

Report the PR URL.

### 7. Update the session file

If `.ai-sessions/` has a session file for this task, update it with `devkit:tracking-sessions`: the commits and the PR URL under "Links", "Current state" (pushed and draft PR opened, or the commands the user still has to run on the host), and "Next steps" (review, the next stacked PR).

## Common mistakes

- Inventing a ticket number.
- `feat` for a refactor or a dependency bump: it cuts a release that ships nothing.
- Committing a failing build "to fix it in the next commit".
- Pushing before the user confirmed.
