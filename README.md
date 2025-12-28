# Azurino

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Configuration

- Buckets: Configure Azure container SAS URLs per bucket name in `:buckets`.
	- Example in [config/local.exs](config/local.exs):
		- config :azurino, buckets: %{"default" => "https://<account>.blob.core.windows.net/<container>?<sas>"}

- Bucket-scoped tokens: Define allowed Bearer tokens per bucket via `:bucket_tokens`.
	- The API expects `Authorization: Bearer <token>` and a `bucket` param/path.
	- Example in [config/local.exs](config/local.exs):
		- config :azurino, :bucket_tokens, %{"default" => ["token-a", "token-b"], "reports" => ["token-c"], "private" => [:all]}
	- Notes:
		- `"bucket" => [:all]` (or "all") allows any token for that bucket.
		- Tokens are only valid for buckets where they are listed.

- Signed URLs: Set `:secret_key` for HMAC signing of temporary download links.
	- Example: config :azurino, :secret_key, "change-me"

See [config/local.exs.template](config/local.exs.template) for a minimal template.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
