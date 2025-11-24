defmodule AzurinoWeb.Api.AzureController do
  use AzurinoWeb, :controller
  alias Azurino.Azure
  alias Azurino.SignedURL

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
        # Generate signed URL instead of exposing SAS URL
        signed_params = SignedURL.sign(
          path: blob_path,
          expires_in: 3600
        )

        json(conn, %{
          status: "success",
          filename: file.filename,
          blob_path: blob_path,
          signed_url: signed_params,
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

  # Generate signed URL for downloading (returns signed URL parameters)
  def download(conn, %{"filename" => filename}) do
    # Generate signed URL instead of exposing SAS URL
    signed_params = SignedURL.sign(
      path: filename,
      expires_in: 3600
    )

    json(conn, %{
      status: "success",
      signed_url: signed_params,
      filename: filename
    })
  end

  # Download file using signed URL verification
  def download_signed(conn, params) do
    storage = Application.get_env(:azurino, :storage_module, Azurino.Azure)

    case SignedURL.verify(params) do
      {:ok, path} ->
        # Signature is valid, first get metadata for caching headers
        case storage.get_blob_metadata(path) do
          {:ok, metadata} ->
            # Check if client has current version via If-None-Match (ETag) or If-Modified-Since
            client_etag = get_req_header(conn, "if-none-match") |> List.first()
            client_modified = get_req_header(conn, "if-modified-since") |> List.first()

            etag = metadata.etag
            last_modified = metadata.last_modified

            # If client has current version, return 304 Not Modified
            cond do
              client_etag && client_etag == etag ->
                conn
                |> put_resp_header("etag", etag)
                |> put_resp_header("last-modified", last_modified || "")
                |> put_resp_header("cache-control", "private, max-age=3600")
                |> send_resp(304, "")

              client_modified && client_modified == last_modified ->
                conn
                |> put_resp_header("etag", etag || "")
                |> put_resp_header("last-modified", last_modified)
                |> put_resp_header("cache-control", "private, max-age=3600")
                |> send_resp(304, "")

              true ->
                # Client doesn't have current version, download and send file
                case storage.download(path) do
                  {:ok, binary} ->
                    filename = Path.basename(path)
                    content_type = metadata.content_type || "application/octet-stream"

                    conn
                    |> put_resp_content_type(content_type)
                    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
                    |> put_resp_header("etag", etag || "")
                    |> put_resp_header("last-modified", last_modified || "")
                    |> put_resp_header("cache-control", "private, max-age=3600")
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

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{status: "error", message: "File not found"})

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{status: "error", message: inspect(reason)})
        end

      {:error, :expired} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{status: "error", message: "Signed URL has expired"})

      {:error, :invalid} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{status: "error", message: "Invalid signature"})

      {:error, :missing_params} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Missing required signature parameters"})
    end
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
