import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :azurino, Azurino.Repo,
  database: Path.expand("../azurino_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :azurino, AzurinoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KMJU70VYuU1kfWXgP3St9oEAhNe/fhLu9AwkLE5oNSMPaFIfNRtcORqW+0kksudQ",
  server: false

# In test we don't send emails
config :azurino, Azurino.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure test secret key for signed URLs
config :azurino, :secret_key, "test-secret-key-for-signed-urls"

# Configure test API token
config :azurino, :api_token, "test-api-token-123"
