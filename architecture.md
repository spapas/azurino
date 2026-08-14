# Azurino Architecture

## Purpose

Azurino is a Phoenix application that sits in front of Azure Blob Storage and offers:

- a browser-based file manager for logged-in users
- a REST API for machine clients
- temporary signed download links for controlled sharing

It is effectively a small gateway layer over Azure Blob Storage rather than a full domain-heavy application.

## High-level structure

```text
Browser user ---> Phoenix browser routes ----\
                                              \
API client ----> Phoenix API routes -----------> Controllers ---> Azurino.Azure ---> Azure Blob Storage
                                              /
Signed link ---> public download route -------/

                           \-> Azurino.SignedURL
                           \-> Azurino.BlobCache
                           \-> Accounts / session auth
```

## Main subsystems

### 1. Web layer

The browser UI lives in Phoenix controllers and HEEX templates.

Relevant files:

- `/home/runner/work/azurino/azurino/lib/azurino_web/router.ex`
- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/azure_page_controller.ex`
- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/azure_page_html.ex`
- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/azure_page_html/azure.html.heex`

Responsibilities:

- list bucket contents
- upload through an HTML form
- download and delete files
- show flash messages and redirect users

Access control:

- these routes are under the browser pipeline plus `:require_authenticated_user`
- authenticated templates use `@current_scope`, following `phx.gen.auth`

### 2. API layer

The JSON API exposes storage operations to external clients.

Relevant files:

- `/home/runner/work/azurino/azurino/lib/azurino_web/router.ex`
- `/home/runner/work/azurino/azurino/lib/azurino_web/controllers/api/azure_controller.ex`
- `/home/runner/work/azurino/azurino/lib/azurino_web/plugs/api_auth.ex`

Responsibilities:

- health endpoints
- file existence checks
- metadata retrieval
- upload/delete/list operations
- signed download generation and fulfillment

Authentication model:

- API clients send `Authorization: ******
- authorization is bucket-scoped through `:bucket_tokens`
- the public signed-download route is intentionally outside API bearer auth

### 3. Storage adapter

Azure Blob interaction is concentrated in:

- `/home/runner/work/azurino/azurino/lib/azurino/azure.ex`

Responsibilities:

- build Azure URLs from configured SAS container URLs
- perform HTTP requests with `Req`
- upload/download/delete blobs
- fetch blob metadata with `HEAD`
- list folders through Azure XML listing endpoints
- parse XML responses with `:xmerl`
- generate unique filenames when collisions occur

Design note:

Controllers usually call a configurable storage module:

`Application.get_env(:azurino, :storage_module, Azurino.Azure)`

This is a deliberate testing seam and should be preserved.

### 4. Signed URL subsystem

Relevant file:

- `/home/runner/work/azurino/azurino/lib/azurino/signer_url.ex`

Responsibilities:

- sign application-level download parameters
- enforce expiration
- verify signatures using HMAC-SHA256
- optionally carry metadata inside the signed parameter set

Why it exists:

- the app avoids handing raw Azure SAS URLs directly to clients
- download access can be time-limited and mediated by Phoenix

### 5. Cache subsystem

Relevant file:

- `/home/runner/work/azurino/azurino/lib/azurino/blob_cache.ex`

Responsibilities:

- cache container listing results in a GenServer for 5 minutes
- reduce repeated Azure list traffic

Current scope:

- cache is keyed by bucket name
- only listing results are cached

### 6. Authentication and accounts

Relevant files:

- `/home/runner/work/azurino/azurino/lib/azurino/accounts.ex`
- `/home/runner/work/azurino/azurino/lib/azurino/accounts/user.ex`
- `/home/runner/work/azurino/azurino/lib/azurino_web/user_auth.ex`

Responsibilities:

- local user accounts
- session management
- login flows
- protected browser routes

This area is standard Phoenix generated auth and is mostly infrastructure for the web UI.

## Request flows

### Browser file listing

1. User authenticates through Phoenix session auth
2. Browser requests `/azure/:bucket`
3. `AzurePageController.index/2` loads folder contents
4. `Azurino.Azure.list_folder/2` queries Azure
5. HEEX template renders folders/files

### API upload

1. Client sends `POST /api/azure/:bucket/upload`
2. `AzurinoWeb.Plugs.ApiAuth` validates bearer token for that bucket
3. API controller resolves storage module
4. `Azurino.Azure.upload/4` uploads to Azure
5. Controller returns blob path plus app-signed download parameters

### Signed download

1. Client obtains signed params from `/api/azure/:bucket/download`
2. Client calls `/api/azure/:bucket/download-signed`
3. Controller verifies HMAC signature and expiration
4. Controller fetches metadata, handles cache headers, downloads blob
5. Binary response is streamed back through Phoenix

## Configuration model

Main configuration lives in:

- `/home/runner/work/azurino/azurino/config/config.exs`
- `/home/runner/work/azurino/azurino/config/runtime.exs`

Important settings:

- `:buckets` -> bucket name to Azure SAS URL
- `:bucket_tokens` -> bucket name to allowed API tokens
- `:secret_key` -> signing key for temporary download links
- `Azurino.Repo` -> SQLite database path and pool settings
- `Azurino.Mailer` -> SMTP in production

## Supervision model

Application startup is defined in:

- `/home/runner/work/azurino/azurino/lib/azurino/application.ex`

Started components:

- telemetry
- Ecto repo
- blob cache GenServer
- migrator
- DNS cluster helper
- Phoenix PubSub
- Phoenix endpoint

## Data model

The database side is intentionally small:

- user/auth tables generated by Phoenix auth
- no large business domain model for blobs
- blob state primarily lives in Azure, not in the local database

This means the application is mostly stateless regarding file metadata except for transient request handling and in-memory caching.

## Testing strategy

The repository uses a mix of:

- controller unit-style tests with mocked storage modules
- route/integration tests for API behavior
- auth-related tests from Phoenix generated code

Key files:

- `/home/runner/work/azurino/azurino/test/azurino_web/controllers/api_azure_controller_test.exs`
- `/home/runner/work/azurino/azurino/test/azurino_web/controllers/api_azure_controller_integration_test.exs`
- `/home/runner/work/azurino/azurino/test/azurino_web/controllers/azure_page_controller_test.exs`

## Architectural constraints

- keep Azure HTTP logic centralized in `Azurino.Azure`
- keep API auth bucket-aware
- preserve the distinction between session-auth browser routes and bearer-auth API routes
- do not assume raw Azure URLs should be exposed to clients
- preserve the configurable storage module seam used by tests

## Areas likely to evolve

- richer operational docs and deployment docs
- stronger observability around Azure failures
- possible refactoring of the browser UI template into cleaner components
- more explicit service boundaries if the project grows beyond a thin gateway
