defmodule AzurinoWeb.Api.AzureController do
  use AzurinoWeb, :controller
  alias Azurino.Azure

  def index(conn, _params) do
    json(conn, %{status: "ok", message: "API is running"})
  end

  def show(conn, %{"id" => id}) do
    json(conn, %{id: id, status: "healthy"})
  end

  # Upload file to Azure Blob Storage
  def upload(conn, %{"file" => file, "folder" => folder}) do
    # file is a Plug.Upload struct with fields: path, filename, content_type
    storage = Application.get_env(:azurino, :storage_module, Azurino.Azure)

    case storage.upload(nil, folder, file.path, file.filename) do
      {:ok, blob_path} ->
        sas_url = Azure.sas_url()

        blob_url =
          case String.split(sas_url || "", "?", parts: 2) do
            [base_url, sas_token] when base_url != "" ->
              base = String.trim_trailing(base_url, "/")
              "#{base}/#{URI.encode(blob_path)}?#{sas_token}"

            [base_url] when base_url != "" ->
              base = String.trim_trailing(base_url, "/")
              "#{base}/#{URI.encode(blob_path)}"

            _ ->
              blob_path
          end

        json(conn, %{
          status: "success",
          filename: file.filename,
          blob_path: blob_path,
          url: blob_url,
          message: "File uploaded successfully"
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: inspect(reason)})
    end
  end

  # Upload without folder parameter (defaults to root)
  def upload(conn, %{"file" => file}) do
    upload(conn, %{"file" => file, "folder" => ""})
  end

  # Generate signed URL for downloading (returns the direct blob URL)
  def download(conn, %{"filename" => filename}) do
    sas_url = Azure.sas_url()

    # Build the blob URL with SAS token
    blob_url =
      case String.split(sas_url, "?", parts: 2) do
        [base_url, sas_token] ->
          base = String.trim_trailing(base_url, "/")
          "#{base}/#{URI.encode(filename)}?#{sas_token}"

        [base_url] ->
          base = String.trim_trailing(base_url, "/")
          "#{base}/#{URI.encode(filename)}"
      end

    json(conn, %{
      status: "success",
      url: blob_url,
      filename: filename,
      # SAS token expiry
      expires_in: 3600
    })
  end

  # Stream file download directly through Phoenix
  def download_stream(conn, %{"filename" => filename}) do
    case Azure.download(filename) do
      {:ok, binary} ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
        |> send_resp(200, binary)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "File not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: inspect(reason)})
    end
  end

  # Delete file from Azure storage
  def delete(conn, %{"filename" => filename}) do
    case Azure.delete(filename) do
      {:ok, _blob_path} ->
        json(conn, %{status: "success", filename: filename, message: "File deleted"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "File not found"})

      {:error, {:http_error, status, body}} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: "HTTP error", code: status, body: inspect(body)})

      {:error, {:request_failed, reason}} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: inspect(reason)})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: inspect(reason)})
    end
  end

  # Check if file exists by attempting to get metadata
  def exists(conn, %{"filename" => filename}) do
    case Azure.get_blob_metadata(filename) do
      {:ok, _metadata} ->
        json(conn, %{exists: true, filename: filename})

      {:error, :not_found} ->
        json(conn, %{exists: false, filename: filename})

      {:error, _reason} ->
        json(conn, %{exists: false, filename: filename})
    end
  end

  # Get file info (size, metadata, etc.)
  def info(conn, %{"filename" => filename}) do
    case Azure.get_blob_metadata(filename) do
      {:ok, metadata} ->
        json(conn, %{
          filename: filename,
          size: metadata.content_length,
          content_type: metadata.content_type,
          last_modified: metadata.last_modified,
          etag: metadata.etag
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "File not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: inspect(reason)})
    end
  end

  # List files in a folder
  def list(conn, %{"folder" => folder}) do
    case Azure.list_folder(folder) do
      {:ok, %{files: files, folders: folders}} ->
        json(conn, %{
          status: "success",
          files: files,
          folders: folders
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: inspect(reason)})
    end
  end

  # List root folder
  def list(conn, _params) do
    list(conn, %{"folder" => ""})
  end
end
