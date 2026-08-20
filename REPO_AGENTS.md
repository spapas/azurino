# Agent Notes for Azurino

This file is for coding agents and maintainers who need a quick repository-specific guide before making changes.

## What this project is

Azurino is a Phoenix 1.8 application that exposes Azure Blob Storage through:

- a browser UI for authenticated users
- a JSON API for token-authenticated clients
- signed download URLs for temporary external access

The app is intentionally small. Most behavior is concentrated in a few modules.

## First files to read

- `/home/runner/work/azurino/azurino/README.md`
- `/home/runner/work/azurino/azurino/API.md`
- `/home/runner/work/azurino/azurino/lib/azurino_web/router.ex`
- `/home/runner/work/azurino/azurino/lib/azurino/azure.ex`
- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/api/azure_controller.ex`
- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/azure_page_controller.ex`

## Important runtime concepts

### 1. Buckets are configuration-driven

Azure containers are configured through app config:

- `:buckets` maps bucket name to Azure container SAS URL
- `:bucket_tokens` maps bucket name to allowed API tokens
- `:secret_key` signs temporary download URLs

Before changing storage behavior, verify how the change interacts with these three settings.

### 2. There are two access paths

- **Web UI**: session auth via `phx.gen.auth`
- **API**: bearer token auth via `AzurinoWeb.Plugs.ApiAuth`

Do not mix the two models accidentally. API changes often belong in `/api` routes and controller code, while UI changes go through authenticated browser routes.

### 3. Azure access is centralized

`/home/runner/work/azurino/azurino/lib/azurino/azure.ex` is the main storage adapter and should stay the source of truth for:

- listing blobs/folders
- uploads
- deletes
- downloads
- metadata retrieval

Prefer extending this module instead of scattering Azure HTTP calls across controllers.

### 4. Signed URLs are application-level, not Azure SAS passthrough

The API does not expose raw Azure SAS download links. It generates its own signed parameters using:

- `/home/runner/work/azurino/azurino/lib/azurino/signer_url.ex`

If you touch download behavior, preserve signature verification and expiration checks.

## Key modules

- `/home/runner/work/azurino/azurino/lib/azurino/azure.ex`  
  Azure Blob operations through `Req`

- `/home/runner/work/azurino/azurino/lib/azurino/blob_cache.ex`  
  5-minute GenServer cache for container listings

- `/home/runner/work/azurino/azurino/lib/azurino_web/plugs/api_auth.ex`  
  bucket-scoped bearer token authorization

- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/api/azure_controller.ex`  
  JSON API entry points

- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/azure_page_controller.ex`  
  browser file management actions

- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/azure_page_html/azure.html.heex`  
  current browser file manager UI

- `/home/runner/work/azurino/azurino/lib/azurino/accounts.ex` and related modules  
  generated user auth and session flows

## Change guidelines

### Prefer small changes in the right layer

- storage logic -> `Azurino.Azure`
- API auth logic -> `AzurinoWeb.Plugs.ApiAuth`
- JSON response shape -> API controller
- browser redirect/flash behavior -> page controller / HEEX template
- route protection -> router scopes and pipelines

### Keep auth rules explicit

When adding routes:

- browser routes that require login belong under `[:browser, :require_authenticated_user]`
- API routes belong under `[:api, AzurinoWeb.Plugs.ApiAuth]` unless intentionally public

### Be careful with filenames and paths

Blob paths are user-facing and may contain folder separators. Changes around:

- `filename`
- `folder`
- signed URL `path`
- `Path.dirname/1`
- `URI.encode/1`

should be reviewed for path handling regressions.

### Avoid bypassing the configured storage module

Controllers often resolve:

`Application.get_env(:azurino, :storage_module, Azurino.Azure)`

Keep that seam intact because tests replace the storage module with mocks.

## Testing guidance

Useful existing test areas:

- `/home/runner/work/azurino/azurino/test/azurino_web/controllers/api_azure_controller_test.exs`
- `/home/runner/work/azurino/azurino/test/azurino_web/controllers/api_azure_controller_integration_test.exs`
- `/home/runner/work/azurino/azurino/test/azurino_web/controllers/api_azure_controller_caching_test.exs`
- `/home/runner/work/azurino/azurino/test/azurino_web/controllers/azure_page_controller_test.exs`

Repository validation command:

- `mix precommit`

For documentation-only changes, full test execution is usually unnecessary unless doc generation or examples are wired into tests.

## Current rough edges worth noticing

- The repository contains both framework-level guidance in `AGENTS.md` and this repository-oriented `REPO_AGENTS.md`
- The browser file manager template currently contains a fair amount of inline JavaScript and inline styling
- The README is still minimal and does not fully document architecture or operational decisions

Treat those as context, not automatic refactoring tasks.
