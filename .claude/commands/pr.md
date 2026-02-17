---
description: Create a pull request using Linear issue context
---

Create a pull request. The changes are already committed and pushed to remote.

Use the PR-DESCRIPTION skill process:
1. Extract Linear issue ID from branch name (format: `username/but-###-description`)
2. Get Linear issue context via `linear issue view BUT-### --json | cat`
3. Check changes with `git diff main..HEAD --stat | cat` and `git log main..HEAD --oneline | cat`
4. Create PR with `gh pr create --base main --title "Title" --body "Description" | cat`
5. Open the PR in browser with `gh pr view --web`

Rules:
- Always pipe commands to `cat` to prevent interactive mode
- Keep PR descriptions short and conversational
- If the PR fixes the issue, add `Fixes BUT-###` at the end
- Do NOT ask for confirmation - create the PR directly
