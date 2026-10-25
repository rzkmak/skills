---
name: implement-go-api
description: Use when creating or restructuring a Go API project with the Gin framework to enforce a standard domain modular layout for large scale applications with cmd internal packages handlers services repositories and middleware
metadata:
  version: "0.1.0"
  stack: "Go >= 1.22, Gin v1.x (current release v1.12.0)"
---
# Implement Go API Skill

Enforce a standard, large-scale layout for Go + Gin API projects: **domain-modular packages under `internal/`**, layered handler → service → repository, with `cmd/` as the only entry point.

References this standard is grounded in:
- `golang-standards/project-layout` (50k+ stars) — `cmd/`, `internal/`, `pkg/` top-level split
- `go-kratos/kratos-layout` — production DDD-influenced internal layering
- Gin official docs (Routing > API Design, Middleware, Binding) — per-resource route registration on `*gin.RouterGroup`, `ShouldBind` preference, middleware scope

## Standard Layout

```
project/
├── go.mod
├── cmd/
│   └── api/
│       └── main.go          # main.go is a composition root: config, DI, router assembly, run
├── internal/
│   ├── server/
│   │   ├── router.go        # gin.New() + global middleware + call Register*Routes
│   │   └── routes.go        # aggregates every domain's Register*Routes(rg) call
│   ├── middleware/          # cross-cutting: auth, logging, recovery, request-id
│   ├── user/                # one folder per domain (user, order, product, ...)
│   │   ├── handler.go       # gin handlers + func RegisterUserRoutes(rg *gin.RouterGroup)
│   │   ├── service.go       # business logic, constructor-injected dependencies
│   │   ├── repository.go    # persistence (or store.go)
│   │   ├── model.go         # domain structs — no transport concerns
│   │   └── dto.go           # request/response structs with `binding:"..."` tags
│   └── platform/            # db, redis, config, logger clients
└── pkg/                     # optional; only truly public/reusable libraries
```

## Rules

1. **`main.go` is a composition root only.** It may load config, construct dependencies, and call the router assembly. It must not define route handlers or call `.GET(`, `.POST(`, or other route-registration methods. Route registration lives in `internal/` handler or route files.
2. **Routes are registered per domain.** Each domain exposes `Register<User|Order|...>Routes(rg *gin.RouterGroup)`; the server aggregates them. No route registration inside `cmd/`.
3. **Dependency flow is one-way:** handler → service → repository. Dependencies are injected through constructors (`NewUserService(repo UserRepository) *UserService`), never through package-level globals.
4. **`gin.Context` stays at the edge.** Only `handler`, `middleware`, `routes`/`router`/`server` files and `cmd/` may reference `gin.Context` or import `gin-gonic/gin`. Service, repository, and model files must not.
5. **Use `ShouldBind*`, never `Bind*`.** `c.BindJSON()` auto-aborts with a 400 before the handler can shape the error response; Gin's docs say to prefer `ShouldBind` for control over error handling.
6. **Transport DTOs are separate from domain models.** `binding:"..."` tags live on request structs (`dto.go` or handler files), never on `model.go` domain structs.
7. **Use `gin.New()` with an explicit `Use(...)` chain in the router, not `gin.Default()`.** The middleware chain must be visible at the assembly point.
8. **No global mutable clients.** No package-level `*sql.DB`, no `http.DefaultClient` in handlers. Clients are constructed in `cmd/` (or `platform/`) and injected.
9. **`internal/` for everything app-specific.** Only genuinely reusable libraries go to `pkg/`.

## Mandatory Verification Step

Before declaring the layout done, validate with the bundled scripts (paths relative to this skill's root):

```bash
# whole project layout
bash scripts/check_layout.sh <path-to-project-dir>

# a single Go file about to be written (handler, service, main, ...)
bash scripts/check_snippet.sh <path-to-file.go>
```

### Retry Limit
If a script exits with a non-zero code, read `stderr`, fix the code, and re-run. Retry at most 5 times — do not loop forever.

If verification still fails after 5 retries, stop retrying and rely on your own judgment:
- If you are confident the layout is valid and the validator is wrong for this case, proceed and state your reasoning next to the change.
- If you are not confident, ask the user how to proceed instead of guessing.

## Antipatterns

| Antipattern | Why it is wrong |
| --- | --- |
| Everything in `main.go` | Does not scale; Gin's API-design docs split routes into per-resource files (`routes/users.go`, `routes/orders.go`) |
| DI via `c.Set("db", db)` + `c.MustGet("db").(*sql.DB)` | Gin's own dependency-injection docs warn this loses compile-time type safety; use constructor injection |
| `c.BindJSON()` for request bodies | `Bind*` auto-aborts with 400; docs say prefer `ShouldBind` for custom error handling |
| `binding:` tags on domain models | Couples transport validation to the persistence schema; DTOs and models must be separate |
| Business logic in middleware | Middleware is for cross-cutting concerns (auth, logging, recovery) on the request path; logic there is untestable in isolation |
| `gin.Default()` in the router | Hides the middleware chain; use `gin.New()` plus explicit `Use(...)` |
| Panics for control flow without `gin.CustomRecovery()` | Default `Recovery()` returns a bare 500; `CustomRecovery` gives controlled error reporting |
| A god `models`/`utils` package every layer imports | Creates import cycles; keep models per domain under `internal/<domain>/` |
| Package-level DB/HTTP clients | Hidden global state; construct in `cmd/` and inject |
