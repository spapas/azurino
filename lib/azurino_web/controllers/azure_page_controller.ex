defmodule AzurinoWeb.AzurePageController do
  use AzurinoWeb, :controller

  def index(conn, %{"path" => path} = params) do
    bucket = Map.get(params, "bucket", conn.params["bucket"] || "default")
    {:ok, %{files: files, folders: contents}} = Azurino.Azure.list_folder(path, bucket)
    render(conn, :azure, %{files: files, folders: contents})
  end

  def index(conn, _params) do
    index(conn, %{"path" => "", "bucket" => conn.params["bucket"] || "default"})
  end

  def metadata(conn, %{"path" => path} = params) do
    bucket = Map.get(params, "bucket", conn.params["bucket"] || "default")

    case Azurino.Azure.get_blob_metadata(path, bucket) do
      {:ok, metadata} ->
        json(conn, metadata)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  def download(conn, %{"path" => path} = params) do
    bucket = Map.get(params, "bucket", conn.params["bucket"] || "default")

    case Azurino.Azure.download(path, bucket) do
      {:ok, body} ->
        send_download(conn, {:binary, body}, filename: Path.basename(path))

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  def download_signed(conn, signed_query) do
    with {:ok, {path, meta}} <-
           Azurino.SignedURL.verify(signed_query, nil, extract_metadata: true),
         bucket <- Map.get(meta, "bucket", conn.params["bucket"] || "default"),
         {:ok, body} <- Azurino.Azure.download(path, bucket) do
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

  def upload(conn, %{"path" => path, "file" => %Plug.Upload{} = upload} = params) do
    # upload.path is the temporary file path on the server
    storage = Application.get_env(:azurino, :storage_module, Azurino.Azure)
    bucket = Map.get(params, "bucket", conn.params["bucket"] || "default")

    case storage.upload(bucket, path, upload.path, upload.filename) do
      {:ok, _blob_path} ->
        conn
        |> put_flash(:info, "Uploaded #{upload.filename} to #{path}")
        |> redirect(to: ~p"/azure/#{bucket}?path=#{path}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Upload failed: #{inspect(reason)}")
        |> redirect(to: ~p"/azure/#{bucket}?path=#{path}")
    end
  end

  def upload(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing file or path"})
  end

  def delete(conn, %{"path" => path} = params) do
    storage = Application.get_env(:azurino, :storage_module, Azurino.Azure)
    bucket = Map.get(params, "bucket", conn.params["bucket"] || "default")

    case storage.delete(path, bucket) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Deleted #{path}")
        |> redirect(to: ~p"/azure/#{bucket}?path=#{Path.dirname(path)}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "File not found: #{path}")
        |> redirect(to: ~p"/azure/#{bucket}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Delete failed: #{inspect(reason)}")
        |> redirect(to: ~p"/azure/#{bucket}")
    end
  end
end
