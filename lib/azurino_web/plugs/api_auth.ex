defmodule AzurinoWeb.Plugs.ApiAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected_token = Application.get_env(:azurino, :api_token)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token == expected_token ->
        conn  # σωστό token, προχωράμε

      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Unauthorized"})
        |> halt()
    end
  end
end
