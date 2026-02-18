# Security Check Patterns

Reference patterns for the security-review skill. Each category lists grep patterns, file types to check, and what constitutes a finding.

---

## 1. Hardcoded Secrets

### Grep Patterns

```
# Generic secrets
(password|passwd|pwd)\s*[:=]\s*['"][^'"]{4,}
(secret|token|api_key|apikey|api-key)\s*[:=]\s*['"][^'"]{4,}
(access_key|private_key|secret_key)\s*[:=]\s*['"][^'"]{4,}
(auth_token|bearer)\s*[:=]\s*['"][^'"]{4,}

# Provider-specific
AKIA[0-9A-Z]{16}                          # AWS Access Key ID
(?:sk|rk)[-_](?:live|test)[-_][a-zA-Z0-9]{20,}  # Stripe keys
ghp_[a-zA-Z0-9]{36}                       # GitHub personal access token
gho_[a-zA-Z0-9]{36}                       # GitHub OAuth token
github_pat_[a-zA-Z0-9_]{22,}              # GitHub fine-grained PAT
xox[bpoas]-[a-zA-Z0-9-]+                  # Slack tokens
sk-[a-zA-Z0-9]{20,}                       # OpenAI API keys
AIza[0-9A-Za-z_-]{35}                     # Google API keys
SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43} # SendGrid API keys
```

### Verification

- Check if `.gitignore` includes `.env`, `.env.*`, `*.pem`, `*.key`
- Check if `.env.example` exists (good practice) vs `.env` committed (bad)
- Look for secrets in CI config files (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`)

### Severity

- **Critical**: Provider-specific key patterns found in source code
- **High**: Generic password/secret assignments with literal values
- **Medium**: Missing `.gitignore` entries for secret files

---

## 2. Environment Variable Exposure

### Frontend Prefix Rules by Framework

| Framework | Public Prefix | Behavior |
|-----------|--------------|----------|
| Next.js | `NEXT_PUBLIC_` | Exposed to browser bundle |
| Vite | `VITE_` | Exposed to browser bundle |
| Create React App | `REACT_APP_` | Exposed to browser bundle |
| Vue CLI | `VUE_APP_` | Exposed to browser bundle |
| Nuxt 3 | `NUXT_PUBLIC_` | Exposed to browser bundle |
| Angular | N/A (uses `environment.ts`) | Check `environment.prod.ts` |
| SvelteKit | `PUBLIC_` | Exposed to browser bundle |

### Sensitive Variable Name Patterns

Variables matching these names should NOT have a public prefix:

```
DATABASE_URL, DB_PASSWORD, DB_HOST
SECRET_KEY, JWT_SECRET, SESSION_SECRET
PRIVATE_KEY, ENCRYPTION_KEY
SMTP_PASSWORD, MAIL_PASSWORD
AWS_SECRET_ACCESS_KEY
STRIPE_SECRET_KEY
API_SECRET, CLIENT_SECRET
REDIS_URL, REDIS_PASSWORD
SENTRY_AUTH_TOKEN
```

### Checks

- Scan `.env*` files for sensitive variable names with public prefixes
- Scan source files for `process.env.NEXT_PUBLIC_` (or equivalent) referencing sensitive names
- Verify server-only files don't import client-side env utilities

### Severity

- **Critical**: Database URL or secret key with public prefix
- **High**: Auth tokens or API secrets with public prefix
- **Medium**: Potentially sensitive variable with public prefix (ambiguous name)

---

## 3. Authentication & Authorization

### JWT Checks

```
# JWT stored in localStorage (XSS-vulnerable)
localStorage\.(setItem|getItem)\s*\(\s*['"].*(?:token|jwt|auth)
sessionStorage\.(setItem|getItem)\s*\(\s*['"].*(?:token|jwt|auth)

# Missing expiration
jwt\.sign\s*\([^)]*(?!expiresIn)         # jwt.sign() without expiresIn
jsonwebtoken.*(?:sign|verify)              # General JWT usage to review

# Weak secrets
jwt\.sign\s*\([^,]+,\s*['"][^'"]{1,15}['"] # Short JWT secret (< 16 chars)
```

### Auth Middleware

```
# Routes without auth middleware — look for route definitions
app\.(get|post|put|patch|delete)\s*\(     # Express routes
router\.(get|post|put|patch|delete)\s*\(  # Express router
@(Get|Post|Put|Patch|Delete)\(            # NestJS decorators
```

Cross-reference with middleware usage: `authenticate`, `requireAuth`, `isAuthenticated`, `protect`, `guard`

### CORS

```
# Overly permissive CORS
(cors|Access-Control-Allow-Origin)\s*[:=(\s]*['"]\*['"]
credentials\s*:\s*true.*origin\s*:\s*true  # Reflects any origin with credentials
```

### Severity

- **High**: JWT in localStorage, missing auth on sensitive routes, CORS wildcard with credentials
- **Medium**: Missing JWT expiration, short JWT secrets

---

## 4. Input Validation & Injection

### SQL Injection

```
# String concatenation in queries
(query|execute|raw)\s*\(\s*['"`].*\$\{    # Template literal in query
(query|execute|raw)\s*\(\s*.*\+\s*        # String concat in query
(query|execute)\s*\(\s*`[^`]*\$\{         # Backtick template in query
\.where\s*\(\s*`[^`]*\$\{                 # ORM raw where with interpolation
```

### XSS

```
# React
dangerouslySetInnerHTML
# Vue
v-html\s*=
# Angular
\[innerHTML\]\s*=
bypassSecurityTrustHtml
# General
\.innerHTML\s*=
document\.write\s*\(
```

### Command Injection

```
# Node.js
(exec|execSync|spawn|spawnSync)\s*\(.*(\$\{|req\.|input|param|query|body)
child_process
# Python
os\.system\s*\(.*(\+|format|f['"])
subprocess\.(call|run|Popen)\s*\(.*shell\s*=\s*True
eval\s*\(
```

### Path Traversal

```
# Unsanitized path construction
(path\.join|path\.resolve)\s*\(.*req\.    # Path from user input
(readFile|readFileSync|createReadStream)\s*\(.*req\.
\.\.\/                                     # Relative path traversal (review context)
```

### Severity

- **Critical**: SQL query with string concatenation from user input, command injection with user input
- **High**: XSS via innerHTML/dangerouslySetInnerHTML with dynamic content, path traversal with user input
- **Medium**: General use of eval, innerHTML with static content

---

## 5. Sensitive Data Handling

### Logging Secrets

```
# Logging sensitive data
(console\.(log|info|warn|error)|logger?\.(log|info|warn|error|debug))\s*\(.*(?:password|secret|token|key|credential|authorization)
(print|puts|println|fmt\.Print)\s*\(.*(?:password|secret|token|key)
```

### Error Exposure

```
# Stack traces in production
(stack|stackTrace|stack_trace).*res\.(send|json|write)
(err|error)\s*\)\s*=>\s*.*res\.(send|json)\s*\(.*err
catch\s*\(.*\)\s*\{[^}]*res\.(send|json)\s*\(\s*(err|error|e)\s*\)
```

### Sensitive Data in URLs

```
# Secrets as query parameters
(password|token|secret|key|api_key)=      # In URL strings
\?(.*&)*(password|token|secret|key)=      # Query param patterns
```

### Missing Security Headers

Check for absence of these headers in server config or middleware:

- `Strict-Transport-Security` (HSTS)
- `Content-Security-Policy` (CSP)
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options`
- `X-XSS-Protection` (legacy but still useful)

Look for `helmet` (Node.js), security middleware usage.

### Severity

- **High**: Logging passwords/tokens, stack traces sent to client in production
- **Medium**: Secrets in URL parameters, missing security headers

---

## 6. Dependency & Configuration

### Debug Mode in Production

```
# Node.js / JavaScript
DEBUG\s*[:=]\s*['"]?\*['"]?               # Debug wildcard
NODE_ENV\s*[:=!]=\s*['"]?development      # Checking for dev mode (review context)
(devtools|debug)\s*:\s*true               # Debug mode enabled

# Python / Django
DEBUG\s*=\s*True

# General
(debug|verbose)\s*[:=]\s*true
```

### Default Credentials

```
# Common default passwords
(password|passwd|pwd)\s*[:=]\s*['"](?:admin|password|123456|root|default|test|changeme)['"]
(username|user)\s*[:=]\s*['"](?:admin|root|test)['"].*(?:password|passwd)\s*[:=]
```

### Weak JWT Secrets

```
(JWT_SECRET|SECRET_KEY|TOKEN_SECRET)\s*[:=]\s*['"](?:.{1,15})['"]  # Less than 16 chars
(JWT_SECRET|SECRET_KEY)\s*[:=]\s*['"](?:secret|changeme|your-secret|default)['"]
```

### Severity

- **Critical**: Default credentials in production config
- **High**: Debug mode enabled in production config, weak JWT secrets
- **Medium**: Debug flags in non-production files (review context)
