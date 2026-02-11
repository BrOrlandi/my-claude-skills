---
name: todo-resolver
description: Find TODO comments in the codebase, analyze their impact and complexity, and optionally implement the changes to resolve them. Use when the user wants to find, triage, or resolve TODO/FIXME/HACK comments.
disable-model-invocation: true
argument-hint: "[path] [--include-fixme] [--include-hack]"
---

# TODO Resolver

Find TODO comments in the codebase, help the user understand their impact, and resolve them.

## Step 1: Discover TODOs

Use Grep to search for TODO comments across the codebase. By default search only for `TODO` patterns. If the user passes `--include-fixme`, also search for `FIXME`. If `--include-hack`, also search for `HACK`.

- Search pattern: `(TODO|FIXME|HACK)` (adjust based on flags)
- If a path argument is provided, scope the search to that path. Otherwise search the entire project.
- Exclude common non-source directories: `node_modules`, `dist`, `build`, `.next`, `vendor`, `.git`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `.claude`
- Use Grep with `output_mode: "content"` and context lines (`-A 2`) to capture surrounding code
- For each match, extract:
  - **File path** and **line number**
  - **Type** (TODO, FIXME, or HACK)
  - **Description** (the text after the keyword)
  - **Author** (if present in format `TODO(author):` or `TODO @author:`)

## Step 2: Present findings

Present all discovered TODOs in a structured summary table grouped by type:

```
### TODOs Found: X total (Y TODO, Z FIXME, W HACK)

| # | Type | File | Line | Description |
|---|------|------|------|-------------|
| 1 | TODO | src/auth/login.ts | 42 | Implement refresh token rotation |
| 2 | FIXME | src/api/users.ts | 118 | Race condition on concurrent updates |
| ... | ... | ... | ... | ... |
```

After the table, ask the user:
- **"Which TODO(s) would you like to analyze in detail? (enter numbers, 'all', or 'none')"**

If no TODOs are found, inform the user and stop.

## Step 3: Deep analysis (per selected TODO)

For each TODO the user selects, perform a detailed analysis:

1. **Read the file** containing the TODO using the Read tool. Read enough surrounding context (at least 50 lines before and after) to understand the code.
2. **Understand the intent**: What does the TODO ask for? What is the current behavior vs the desired behavior?
3. **Trace dependencies**: Use Grep and Read to find:
   - Other files that import or reference the function/module containing the TODO
   - Related tests that cover this code
   - Similar patterns elsewhere in the codebase that might be affected
4. **Assess complexity**:
   - **Size**: Small (< 20 lines changed), Medium (20-100 lines), Large (100+ lines)
   - **Risk**: Low (isolated change), Medium (touches shared code), High (affects critical paths or public APIs)
   - **Files affected**: List all files that would need changes

Present the analysis for each selected TODO:

```
### TODO #1: Implement refresh token rotation
**File:** `src/auth/login.ts:42`
**Size:** Medium (~40 lines)
**Risk:** High (affects authentication flow)
**Files affected:**
- `src/auth/login.ts` (main change)
- `src/auth/tokens.ts` (add rotation logic)
- `src/middleware/auth.ts` (update token validation)
- `tests/auth/login.test.ts` (add test cases)

**Current behavior:** Access tokens are issued but never rotated. Refresh tokens are reused indefinitely.
**Desired behavior:** Implement one-time-use refresh tokens that rotate on each use, invalidating the previous token.
**Approach:** [brief implementation plan]
```

After presenting all analyses, ask the user:
- **"Which TODO(s) would you like me to resolve? (enter numbers or 'none')"**

## Step 4: Implement resolution

For each TODO the user wants resolved:

1. **Read all affected files** fully before making changes
2. **Implement the change** following existing code style and patterns in the project
3. **Remove the TODO comment** after resolving it
4. **Update or add tests** if test files exist for the affected code
5. **Fix imports** if new files or modules are created

Rules:
- Preserve existing code style (indentation, naming conventions, patterns)
- Do not refactor surrounding code beyond what the TODO requires
- If the TODO is ambiguous, ask the user for clarification before implementing
- If resolving one TODO conflicts with another TODO, inform the user
- Make the minimal change necessary to fully address the TODO

## Step 5: Summary

After all selected TODOs are resolved, present a summary:

```
### Resolution Summary

| # | TODO | Status | Files Changed |
|---|------|--------|---------------|
| 1 | Implement refresh token rotation | Resolved | 4 files |
| 3 | Add input validation | Resolved | 2 files |
| 5 | Fix race condition | Skipped (user) | - |

**Total:** 2 resolved, 1 skipped, X remaining in codebase
```

Remind the user to run tests and review the changes before committing.
