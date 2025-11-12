defmodule Azurino.Repo do
  use Ecto.Repo,
    otp_app: :azurino,
    adapter: Ecto.Adapters.SQLite3
end
