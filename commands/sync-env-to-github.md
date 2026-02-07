# Sync Environment Variables to GitHub

Add or update environment secrets on GitHub for the Production and staging environments using the `gh` CLI.

## Instructions

When the user asks to sync, add, or update environment variables on GitHub, follow these steps:

### 1. Identify the variables and values

- The user will specify which env var names to sync (e.g., `MICROSOFT_CLIENT_ID`, `NEW_API_KEY`).
- Look for values in these local files (in order of priority):
  1. `.env.production.local` and `.env.staging.local` (if different per environment)
  2. `apps/api/.env` (shared dev values)
  3. `apps/api/.env.example`
- If values are empty in local files, ask the user to provide them.
- If the same value should be used for both environments, confirm with the user.

### 2. Set the secrets on GitHub

Use `gh secret set` with the `--env` flag for each environment. Pipe the value via echo to avoid it appearing in shell history:

```bash
echo "VALUE" | gh secret set VAR_NAME --env Production
echo "VALUE" | gh secret set VAR_NAME --env staging
```

The GitHub environments for this repo are:
- **Production** (case-sensitive)
- **staging** (case-sensitive, lowercase)
- **Preview** (case-sensitive, exists but rarely used for secrets)

### 3. Verify the secrets were set

```bash
gh secret list --env Production | grep VAR_NAME
gh secret list --env staging | grep VAR_NAME
```

### 4. Update local env template files

After setting secrets on GitHub, also update the env template/example files if the variable is new:
- `.env.production.example` - add the variable name with empty value
- `.env.staging.example` - add the variable name with empty value
- `.env.production.local` - add the variable name (with or without value)
- `.env.staging.local` - add the variable name (with or without value)
- `apps/api/.env.example` - add the variable name with the value or a placeholder

### 5. Summary

After completion, list:
- Which variables were set
- Which environments were updated
- Remind the user to re-deploy if the running services need the new variables

## Example usage

User: "Add STRIPE_API_KEY to github environments with value sk_live_xxx"

Actions:
1. `echo "sk_live_xxx" | gh secret set STRIPE_API_KEY --env Production`
2. `echo "sk_live_xxx" | gh secret set STRIPE_API_KEY --env staging`
3. Verify with `gh secret list --env Production | grep STRIPE_API_KEY`
4. Update `.env.production.example`, `.env.staging.example`, etc.

## Notes

- Secrets are write-only on GitHub - you cannot read their values back, only verify they exist.
- The repo is `beuni-tecnologia/new-dashboard`.
- All env vars for this project are stored as **environment secrets** (not environment variables or repo-level secrets).
- Use `gh secret list --env <ENV_NAME>` to see all current secrets for an environment.
