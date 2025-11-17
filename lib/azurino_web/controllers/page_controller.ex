defmodule AzurinoWeb.PageController do
  use AzurinoWeb, :controller

  def home(conn, %{"path" => path}) do
    {:ok, %{files: files, folders: contents}} = Azurino.Azure.list_folder(path)
    render(conn, :home, %{files: files, folders: contents})
  end

  def home(conn, _params) do
    home(conn, %{"path" => ""})
  end

  def metadata(conn, %{"path" => path}) do
    case Azurino.Azure.get_blob_metadata(path) do
      {:ok, metadata} ->
        json(conn, metadata)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  def download(conn, %{"path" => path}) do
    case Azurino.Azure.download(path) do
      {:ok, body} ->
        send_download(conn, {:binary, body}, filename: Path.basename(path))

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  def download_signed(conn, signed_query) do
    with {:ok, path} <- Azurino.SignedURL.verify(signed_query),
         {:ok, body} <- Azurino.Azure.download(path) do
      send_download(conn, {:binary, body}, filename: Path.basename(path))
    else
      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{error: "Το link έχει λήξει"})

      {:error, :invalid} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Μη έγκυρη υπογραφή"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)

        |> json(%{error: inspect(reason)})
    end
  end
end
