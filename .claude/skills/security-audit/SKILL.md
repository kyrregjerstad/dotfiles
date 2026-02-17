---
name: security-audit
description: Perform security vulnerability analysis on codebases. Identifies injection flaws, XSS, authentication issues, business logic vulnerabilities, and misconfigurations. Uses static code analysis and pattern matching. Outputs findings to markdown report. Use when user asks to audit code security, find vulnerabilities, check for security issues, or run security analysis on a repo or path.
---

# Security Audit Skill

Analyze code for security vulnerabilities, outputting findings to a markdown report.

## Workflow

1. **Scope determination** - Identify target path (default: current working directory)
2. **Static analysis** - Pattern-based code scanning
3. **Report generation** - Write findings to `SECURITY_AUDIT.md`

## Step 1: Static Analysis Patterns

Search for these vulnerability patterns using Grep tool:

### Injection Vulnerabilities
- SQL: `query\s*\(.*\$|execute\s*\(.*\+|raw\s*\(`
- Command: `exec\s*\(|spawn\s*\(|system\s*\(` without sanitization
- Template: `\$\{.*\}.*innerHTML|v-html=|dangerouslySetInnerHTML`

### XSS Patterns
- `innerHTML\s*=`
- `document\.write\s*\(`
- `\.html\s*\(` (jQuery)
- `dangerouslySetInnerHTML`
- Unescaped template variables

### Authentication Issues
- Hardcoded secrets: `(api[_-]?key|password|secret|token)\s*[:=]\s*['"][^'"]{8,}`
- Weak JWT: `algorithm.*none|HS256` without proper validation
- Missing auth checks on routes

### Business Logic
- Race conditions: async operations without locks on shared state
- IDOR: Direct object references from user input without ownership check
- Mass assignment: Spreading user input directly into DB operations

### Misconfigurations
- CORS: `Access-Control-Allow-Origin.*\*`
- Debug mode: `debug\s*[:=]\s*true|NODE_ENV.*development` in prod configs
- Exposed secrets in configs: `.env` files, hardcoded credentials
- Missing security headers

## Step 2: File-Specific Checks

Check these files if present:
- `package.json` - outdated deps, missing lockfile
- `.env*` files - should be in .gitignore
- `*config*.{js,ts,json}` - exposed secrets, debug flags
- Auth middleware - proper token validation
- API routes - input validation, auth guards

## Report Format

Write to `SECURITY_AUDIT.md`:

```markdown
# Security Audit Report

**Target:** [path]
**Date:** [date]
**Scope:** [files analyzed count]

## Summary

| Severity | Count |
|----------|-------|
| Critical | X     |
| High     | X     |
| Medium   | X     |
| Low      | X     |

## Findings

### [CRITICAL/HIGH/MEDIUM/LOW] - Finding Title

**Location:** `file:line`
**Type:** [Injection/XSS/Auth/Config/Logic]
**Description:** Brief description of the vulnerability

**Evidence:**
\`\`\`
[relevant code snippet]
\`\`\`

---
[repeat for each finding]

## Files Analyzed
- [list key files checked]
```

## Severity Classification

- **Critical**: RCE, SQL injection, auth bypass, exposed secrets in prod
- **High**: XSS, CSRF, IDOR, weak crypto
- **Medium**: Info disclosure, missing headers, verbose errors
- **Low**: Debug code, outdated deps (no known CVE), minor misconfigs

## Execution Notes

- Skip `node_modules/`, `vendor/`, `.git/`, build outputs
- Focus on source files: `.ts`, `.js`, `.go`, `.py`, `.jsx`, `.tsx`
- Check max 500 files to avoid context overflow
- Group similar findings (e.g., 10 instances of same pattern = 1 finding)
