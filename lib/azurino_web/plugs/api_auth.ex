defmodule AzurinoWeb.Plugs.ApiAuth do
  @moduledoc """
  API Bearer token authentication scoped by bucket.

  Configuration
  - Uses `:bucket_tokens` app env: a map of `bucket => [tokens]`.
  - Use `:all` or "all" to allow any token for a given bucket.

  Request requirements
  - Header: `Authorization: Bearer <token>`
  - Bucket: provided via path params or query/body params under `"bucket"`.

  Outcomes
  - 401 Unauthorized when header is missing or token not allowed.
  - 403 Forbidden when the bucket does not allow the token or bucket is unknown.

  Example config:

      config :azurino, :bucket_tokens, %{
        "default" => ["token-a", "token-b"],
        "reports" => ["token-c"],
        "private" => [:all]
      }
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    tokens_config = Application.get_env(:azurino, :bucket_tokens) || %{}

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         :ok <- authorize(token, bucket_from(conn), tokens_config) do
      conn
    else
      [] ->
        unauthorized(conn, "Missing Authorization header")

      {:error, :invalid_token} ->
        unauthorized(conn, "Unauthorized")

      {:error, :forbidden_bucket} ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(%{error: "Token not allowed for bucket"})
        |> halt()

      _ ->
        unauthorized(conn, "Unauthorized")
    end
  end

  defp authorize(_token, _bucket, nil), do: {:error, :invalid_token}

  defp authorize(token, bucket, %{} = tokens_by_bucket) when is_binary(token) do
    with true <- is_binary(bucket),
         allowed when not is_nil(allowed) <- Map.get(tokens_by_bucket, bucket) do
      case allowed do
        :all -> :ok
        "all" -> :ok
        list when is_list(list) -> if Enum.member?(list, token), do: :ok, else: {:error, :invalid_token}
        single -> if single == token, do: :ok, else: {:error, :invalid_token}
      end
    else
      _ -> {:error, :forbidden_bucket}
    end
  end

  defp bucket_from(conn) do
    conn.path_params["bucket"] || conn.params["bucket"]
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: message})
    |> halt()
  end
end
