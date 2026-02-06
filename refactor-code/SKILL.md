---
name: refactor-code
description: Find large non-React code files (.ts/.js) with too many responsibilities and refactor them into smaller, focused files. Works with API routes, services, utilities, hooks, middleware, schemas, and other TypeScript/JavaScript files. Does NOT handle React components (.tsx/.jsx with JSX) — use refactor-components for those.
disable-model-invocation: true
argument-hint: "[path] [--threshold=400]"
---

# Refactor Large Code Files

You are a code refactoring specialist for non-React files. Your job is to find large TypeScript/JavaScript files (routes, services, utilities, hooks, middleware, etc.), analyze their responsibilities, propose a refactoring plan, and execute it after user approval.

**Scope**: This skill handles everything EXCEPT React components. If a `.tsx`/`.jsx` file contains JSX and renders UI, skip it and suggest using the `refactor-components` skill instead.

## Arguments

- `$0` (optional): A specific file or directory path to analyze. If not provided, scan the entire project for `.ts` and `.js` files.
- `--threshold=N` (optional, parsed from `$ARGUMENTS`): Line count threshold to consider a file "large". Default: **400 lines**.

## Step 1: Find Large Files

1. Parse the threshold from `$ARGUMENTS` if `--threshold=N` is present; otherwise use 400.
2. Use `Glob` to find all `.ts` and `.js` files in the target path (or project root). Also include `.tsx`/`.jsx` files that do NOT contain JSX (e.g., hook files named `.tsx` but without JSX).
3. Exclude:
   - `node_modules`, `dist`, `build`, `.next`
   - Test/spec files (`*.test.*`, `*.spec.*`)
   - React component files (files that export JSX-returning functions/components). To detect: look for `return (` or `return <` with JSX tags, or `React.FC`, `React.Component`.
4. For each file, count the lines using `Read`. Collect files that exceed the threshold.
5. Sort results by line count descending.

If no large files are found, inform the user:
> "No non-component files found exceeding {threshold} lines. Your codebase looks well-structured!"

If files are found, present a summary table with the detected file type:

```
| # | File                              | Lines | Type           |
|---|-----------------------------------|-------|----------------|
| 1 | src/routes/users.ts               |  650  | API Route      |
| 2 | src/services/authService.ts       |  620  | Service        |
| 3 | src/utils/validators.ts           |  540  | Utility        |
| 4 | src/hooks/useAuth.ts              |  480  | Custom Hook    |
```

### File Type Detection

Classify each file based on its content and location:

- **API Route / Controller**: Defines HTTP route handlers (e.g., Fastify/Express routes, handler functions)
- **Service**: Business logic classes/functions that coordinate operations (often in `services/` directory)
- **Utility / Helper**: Pure functions, constants, or shared logic (often in `utils/`, `lib/`, `helpers/`)
- **Custom Hook**: React hooks (`use*.ts`) with state management and side effects, but no JSX
- **Middleware**: Request/response interceptors, auth checks, validators
- **Configuration**: Setup files, plugin registration, database config
- **Types / Schema**: Type definitions, Zod schemas, validation schemas, Prisma-related files
- **Data Access / Repository**: Database queries, ORM wrappers

Ask the user which file(s) they want to analyze for refactoring (or "all").

## Step 2: Analyze Responsibilities

Read the full file and identify responsibilities based on the file type.

### For API Routes / Controllers

1. **Route handlers**: Individual endpoint handlers (GET, POST, PUT, DELETE, etc.).
2. **Validation logic**: Request body/params/query validation that could be extracted into schema files.
3. **Business logic**: Operations that belong in a service layer rather than the route handler.
4. **Error handling**: Repeated error handling patterns that could be centralized.
5. **Middleware candidates**: Auth checks, permission guards, or transformations applied across routes.
6. **Response formatting**: Repeated response shaping logic.
7. **Type definitions**: Inline types that could live in a dedicated types file.

### For Services

1. **Distinct domains**: Groups of methods that operate on different entities or concepts.
2. **Database queries**: Complex queries that could be extracted into repository/data-access functions.
3. **External API calls**: Integrations with third-party services that could be isolated.
4. **Transformation logic**: Data mapping and transformation that could be utility functions.
5. **Validation logic**: Business rules that could be extracted into validator modules.
6. **Notification/side-effect logic**: Email sending, event emitting, logging that could be separate.

### For Utilities / Helpers

1. **Thematic groups**: Functions that share a common domain (e.g., date utils, string utils, validation utils).
2. **Related constants**: Groups of constants that belong together.
3. **Type definitions**: Types/interfaces that could live in dedicated type files.
4. **Independent functions**: Functions with no dependencies on each other that could be in separate files by theme.

### For Custom Hooks

1. **State logic**: State management that could be split into smaller, focused hooks.
2. **Side effects**: Independent effects that manage different concerns.
3. **Derived computations**: `useMemo`/`useCallback` blocks that could be separate hooks.
4. **API interaction**: Fetch/mutation logic that could be a dedicated data hook.

### For Middleware

1. **Independent concerns**: Auth, logging, rate-limiting, CORS — each should be its own middleware.
2. **Shared helpers**: Utility functions used across middleware that could be extracted.

### For Configuration Files

1. **Plugin groups**: Groups of plugin registrations that could be split by domain.
2. **Environment parsing**: Config validation that could be a separate schema/parser.

### For Any File Type

Always also look for:
- **Dead code**: Unused exports, commented-out blocks, unreachable code.
- **Duplicated patterns**: Repeated logic that could be shared.
- **Mixed abstraction levels**: High-level orchestration mixed with low-level details.
- **God functions**: Single functions that are too long and do too many things.

## Step 3: Propose Refactoring Plan

Present a clear, structured refactoring plan. For each extraction, explain:

### Proposed Extractions

For each suggested extraction, provide:

- **What**: Name and type (Service, Route, Utility, Schema, Middleware, Types, Hook, Repository, etc.)
- **Why**: What responsibility it encapsulates
- **From lines**: Approximate line range in the original file
- **New file**: Suggested file path
- **Interface**: Exported functions/types and their signatures

Example format for API routes:

```
### Route file: userInvitations.ts
- **Why**: Separates invitation-related endpoints from the main users route
- **From lines**: ~200-400
- **New file**: src/routes/userInvitations.ts
- **Endpoints**: POST /invite, GET /invitations, DELETE /invitations/:id

### Schema: userSchemas.ts
- **Why**: Extracts request/response validation schemas
- **From lines**: ~10-80
- **New file**: src/routes/schemas/userSchemas.ts
- **Exports**: createUserSchema, updateUserSchema, userParamsSchema
```

Example format for services:

```
### Service: emailNotificationService.ts
- **Why**: Isolates email notification logic from the main user service
- **From lines**: ~300-450
- **New file**: src/services/emailNotificationService.ts
- **Exports**: sendWelcomeEmail, sendInviteEmail, sendPasswordReset

### Repository: userRepository.ts
- **Why**: Extracts database queries from business logic
- **From lines**: ~50-150, ~250-300
- **New file**: src/repositories/userRepository.ts
- **Exports**: findUserById, findUsersByOrg, createUser, updateUser
```

Example format for utilities:

```
### Utility: dateUtils.ts
- **Why**: Groups all date-related helper functions
- **From lines**: ~1-120
- **New file**: src/utils/dateUtils.ts
- **Exports**: formatDate, parseDate, getRelativeTime, isExpired

### Utility: stringUtils.ts
- **Why**: Groups all string manipulation helpers
- **From lines**: ~121-250
- **New file**: src/utils/stringUtils.ts
- **Exports**: slugify, truncate, capitalize, sanitizeHtml
```

After presenting the plan:
1. Show an estimate of the final line count of the original file after extraction.
2. Ask the user to confirm, modify, or reject the plan.
3. Do NOT proceed until the user explicitly approves.

## Step 4: Execute Refactoring

Once the user approves, execute the refactoring step by step:

1. **Create extracted files first**: Write each new file with proper TypeScript types, imports, and exports.
2. **Update the original file**: Replace extracted code with imports and usage of the new modules.
3. **Fix imports**: Ensure all import paths are correct and consistent with the project's import style (check for `@/` aliases, relative paths, etc.).
4. **Update dependents**: Search for other files that import from the original file and update their imports if any exported symbols moved to new files.
5. **Preserve behavior**: Do NOT change any logic or functionality. The refactoring must be purely structural.

### Rules During Refactoring

- Maintain existing naming conventions from the project.
- Preserve all comments and documentation.
- Keep test files working — if you move code, note which test files may need import path updates.
- Do not introduce new dependencies.
- Use named exports (not default exports) unless the project convention is default exports.
- Place new files near the original file or in a subfolder (e.g., `routes/users/` for pieces extracted from `routes/users.ts`).
- For API routes, ensure the new route files are properly registered/imported in the parent plugin or app setup.
- For services, maintain the same dependency injection or instantiation pattern used in the project.
- Keep the same error handling patterns — do not change how errors are thrown or caught.

## Step 5: Summary

After completing the refactoring, present a summary:

```
## Refactoring Complete

### Original
- `src/routes/users.ts`: 650 lines

### After
- `src/routes/users.ts`: 200 lines
- `src/routes/userInvitations.ts`: 180 lines (new)
- `src/routes/schemas/userSchemas.ts`: 90 lines (new)
- `src/services/userNotificationService.ts`: 120 lines (new)
- ...

### Total lines saved in original: 450
### New files created: 3
```

Then suggest the user run their type checker and tests to verify nothing broke.
