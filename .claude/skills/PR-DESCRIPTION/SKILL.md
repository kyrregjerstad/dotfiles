---
name: PR-DESCRIPTION
description: Generate a description of a PR using Linear issue context.
---

Create pull requests using GitHub CLI, always targeting the `main` branch unless specified otherwise.

Always use `| cat` after commands, to ensure you don't get the interactive mode.

## Process
1. **Extract Linear issue ID from branch name**:
   Branch format: `username/but-814-description` → Issue ID: `BUT-814`
   ```bash
   git branch --show-current | cat
   ```

2. **Get Linear issue context** (using linear-cli skill):
   ```bash
   linear issue view BUT-814 --json | cat
   ```
   
   This returns JSON with fields like: `identifier`, `title`, `description`, `state`, `priority`, etc.

3. **Check changes**:
   ```bash
   git diff main..HEAD --stat | cat
   git log main..HEAD --oneline | cat
   ```

4. **Create PR**
   ```bash
   gh pr create --base main --title "Title" --body "Description" | cat
   ```

## Rules
- **Always pipe `gh` and `git` commands to `cat`** to prevent interactive mode
- Keep PR descriptions short and conversational
- Extract Linear issue ID from branch name (format: `username/but-###-description`)
- Use Linear issue title/description for context when available
- If the PR fixes the issue, add `Fixes BUT-###` at the end of the description
- **Don't include file changes list** - focus only on what was accomplished
- **Never include a test plan** unless the user specifically asks for one
- Use the `linear-cli` skill for all Linear operations

## Example
Branch: `kyrre/but-814-fix-ci-tests`
→ Extract issue ID `BUT-814` → Get Linear issue details → Generate PR description → Ask confirmation → Create PR