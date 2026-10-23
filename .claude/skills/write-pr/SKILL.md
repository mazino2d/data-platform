---
name: write-pr
description: Branch, commit, push and open a GitHub pull request for this repo with a well-structured title and description. Use when the user asks to "create a PR", "open a PR", "write a PR description", "tạo PR", or to ship the current changes.
---

# Write a pull request

Open a PR against `main` for the current changes, following this repo's conventions (see `CLAUDE.md` → Git & Pull Requests).

## 1. Prepare the branch

1. `git status` and `git diff` (staged + unstaged) to see what will ship. Do not include unrelated files, secrets (`.env`) or local artefacts (`gha-creds-*.json`, `site/`, `dbt/target/`).
2. If on `main`, create a branch: `<type>/<short-kebab-desc>`.
3. If SQL changed, run `make lint` (or `make fix`) first.

## 2. Commit

- Conventional Commits subject, imperative, ≤ 72 chars: `feat: …`, `fix: …`, `docs: …`, `chore: …`, `refactor: …`, `ci: …`.
- The body explains *why*, then a short bullet list of *what*.
- Pre-commit hooks run on commit (sqlfluff can take ~2 min). Never use `--no-verify`. If a hook fails or rewrites files, fix/re-stage and create a **new** commit.

## 3. Write the PR

The title is the same Conventional Commits line, because PRs are squash-merged and the title becomes the commit on `main`.

Body template (English, Markdown). Drop any section that has nothing to say:

```markdown
## Why
<1–3 sentences: the problem or motivation, with context a reviewer lacks.>

## What
- **`path/or/component`**: <change and its reason>
- ...

## Notes
<Follow-ups, things intentionally left out, manual steps after merge, breaking changes.>

## Test plan
- [ ] <CI job that must pass, e.g. `CI / dbt`, `CI / lint / gate`>
- [ ] <Manual verification, e.g. `make pipeline` against a dev dataset>
```

Guidelines:
- Describe the change for a reviewer who has not seen the conversation. Do not narrate how you got there.
- Name files and components, not line numbers. Keep it scannable, short enough to read in under a minute.
- Say which workflows the PR triggers (`ci.yml`, `docs.yml`, generated `dag-*.yml`) and anything that happens on merge (e.g. a docs deploy, a new scheduled pipeline).
- End the body with the attribution line given in the session's system reminder, if there is one.

## 4. Push and open

```bash
git push -u origin <branch>
gh pr create --base main --title "<title>" --body-file - <<'EOF'
<body>
EOF
```

Return the PR URL. If asked, watch checks with `gh pr checks <n>` and report failures together with their log excerpt (`gh run view <id> --log-failed`).
