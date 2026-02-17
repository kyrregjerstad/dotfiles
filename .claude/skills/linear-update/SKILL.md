---
name: Linear Project Update
description: Transform draft notes into polished Linear project updates. Use when user wants to write a project update, status update, or transform rough notes into a formatted update for Linear. Triggers on phrases like "project update", "status update", "write an update", or when user provides draft notes to polish.
---

# Linear Project Update Generator

Transform draft notes into polished project updates.

## Output

Save to: `~/linear-updates/YYYY-MM-DD-projectName-update.md`

After saving, copy the content to clipboard using `pbcopy`.

## Format

Always use markdown formatting with these headings:

```md
## What we shipped

[Accomplishments, completed work, key wins]

## Coming up

[Next steps, upcoming work]
```

Use bullet lists, bold text, and other markdown features where appropriate.

## Rules

- User input is likely from dictation. Expect transcription errors. Use context to infer what was actually meant.
- Keep it brief: enough context without padding
- Cover: what happened + what's next
- Write for someone unfamiliar with details
- Lead with most important info
- Include bad news. Updates prevent surprises
- Don't list issues; explain what they accomplished
- No em dashes or en dashes. Use commas or periods
- No emojis
- Ask clarifying questions if needed

## Context Gathering

If draft lacks context, use `linear-cli` skill:
- `linear project view <id>` - project details
- `linear issue list --project <id>` - recent issues
- GraphQL API for cycle progress (see linear-cli skill)

## Example

**Draft:**
"finished the auth refactor finally, took longer than expected because we found some edge cases with SSO tokens. maria is out next week so the admin panel work will slip. should still hit the milestone but it's tight."

**Output:** `2025-01-16-auth-update.md`

```md
## What we shipped

Completed the auth refactor. SSO token edge cases added unexpected scope but it is done now.

## Coming up

Admin panel work will slip next week due to team availability. Milestone is still achievable but we have lost our buffer.
```

---

Transform the user's draft into a Linear project update.
