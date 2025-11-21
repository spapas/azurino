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

  def upload(conn, %{"path" => path, "file" => %Plug.Upload{} = upload}) do
    # upload.path is the temporary file path on the server
    storage = Application.get_env(:azurino, :storage_module, Azurino.Azure)

    case storage.upload(nil, path, upload.path, upload.filename) do
      {:ok, _blob_path} ->
        conn
        |> put_flash(:info, "Uploaded #{upload.filename} to #{path}")
        |> redirect(to: ~p"/?path=#{path}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Upload failed: #{inspect(reason)}")
        |> redirect(to: ~p"/?path=#{path}")
    end
  end

  def upload(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing file or path"})
  end

  def delete(conn, %{"path" => path}) do
    storage = Application.get_env(:azurino, :storage_module, Azurino.Azure)

    case storage.delete(path) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Deleted #{path}")
        |> redirect(to: ~p"/?path=#{Path.dirname(path)}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "File not found: #{path}")
        |> redirect(to: ~p"/")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Delete failed: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end
  end
end
