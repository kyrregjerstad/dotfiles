---
name: review-staged-code
description: >
  Review code currently staged in Git (git diff --cached). Performs thorough code review
  focusing on bugs, security issues, best practices, and style guide compliance.
  Use when user asks to review staged changes, review before commit, or code review
  of pending changes. Triggers: "review staged", "review my changes", "check my code",
  "/review-staged-code", "review before commit".
---

# Review Staged Code

Review Git staged changes for quality, correctness, and style compliance.

## Process

1. **Assess staged changes**
   ```bash
   git diff --cached --stat
   ```
   If no staged changes, inform user and stop.

   If diff is large (>1000 lines or >10 files):
   - Review file-by-file instead of all at once
   - Skip generated files (*.lock, *.gen.ts, dist/, node_modules, etc.)
   - Prioritize: core logic → tests → types → config
   - Maintain a running summary across file reviews

   For normal-sized diffs, get the full diff:
   ```bash
   git diff --cached
   ```

2. **Read project style guide**
   Check for CLAUDE.md in repo root. If present, read and apply its conventions.

3. **Load relevant project documentation**
   Check for `./docs/` directory. If present:
   - List available docs to understand what's documented
   - Based on the staged changes, identify which docs are relevant:
     - Changed a React component? Read UI/component docs
     - Changed API routes? Read API docs
     - Changed database code? Read data model docs
   - Only load docs that directly relate to the code being reviewed
   - Skip unrelated docs (e.g., don't read Kubernetes docs when reviewing React code)

4. **Understand the surrounding context**
   Before reviewing, gather context on how the changed code connects to the system:
   - Read the full files being modified (not just the diff hunks)
   - Find callers/consumers of modified functions/components
   - Check what the modified code calls or depends on
   - Look at related tests if they exist
   - Understand the data flow and state management around the changes

   This prevents surface-level reviews that miss integration issues.

5. **Review the code** examining:

   **Correctness**
   - Logic errors, off-by-one, null/undefined handling
   - Race conditions, async/await issues
   - Edge cases not handled

   **Security**
   - Injection vulnerabilities (SQL, command, XSS)
   - Hardcoded secrets, credentials
   - Unsafe deserialization, eval usage

   **Best Practices**
   - DRY violations, dead code
   - Proper error handling
   - Meaningful names, clear intent
   - Appropriate abstractions (not over/under-engineered)

   **Style Guide Compliance**
   - Follow CLAUDE.md conventions if present
   - Consistent formatting, naming conventions
   - Import organization

   **Performance**
   - Unnecessary re-renders (React)
   - N+1 queries, missing indexes
   - Memory leaks, unbounded growth

   **Integration**
   - Breaking changes to public APIs or interfaces
   - Mismatched assumptions with callers/consumers
   - Missing updates to related code that should change together
   - State management inconsistencies
   - Type mismatches at boundaries

6. **Report findings**

   Format:
   ```
   ## Summary
   [1-2 sentence overview]

   ## Issues Found

   ### Critical
   1. **file:line** - Description and fix
   2. **file:line** - Description and fix

   ### Warnings
   3. **file:line** - Description and suggestion
   4. **file:line** - Description and suggestion

   ### Suggestions
   5. **file:line** - Optional improvement

   ## What Looks Good
   [Brief positive notes if applicable]
   ```

   Use continuous numbering across all sections for easy reference (e.g., "fix issue #3").

   If no issues: "Staged changes look good. No issues found."

## Guidelines

- Be specific: reference exact file and line numbers from the diff
- Explain WHY something is an issue, not just WHAT
- Provide concrete fix suggestions
- Distinguish severity: critical (must fix) vs warnings vs suggestions
- Don't nitpick style if no style guide exists
- Focus on the actual changes, not surrounding unchanged code
- Use context7 MCP server to look up latest library docs when unsure about correct API usage, best practices, or deprecations
- Use sub-agents (Task tool) liberally for parallel work: exploring callers/consumers, searching for patterns, reading related files, checking test coverage
