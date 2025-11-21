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
    case Azure.upload(nil, folder, file.path) do
      {:ok, blob_path} ->
        json(conn, %{
          status: "success",
          filename: file.filename,
          blob_path: blob_path,
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
    blob_url = case String.split(sas_url, "?", parts: 2) do
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
      expires_in: 3600  # SAS token expiry
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

  # Delete file from Azure storage (not implemented in Azure module yet)
  def delete(conn, %{"filename" => _filename}) do
    # Azure module doesn't have delete yet
    # You'd need to implement it using DELETE verb to blob URL

    json(conn, %{
      status: "error",
      message: "Delete not implemented yet"
    })
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
