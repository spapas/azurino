defmodule Azurino.Azure do
  require Logger
  @moduledoc "List Azure container blobs via SAS URL"
  @sas_url Application.compile_env(:azurino, :sas_url)

  def sas_url, do: @sas_url

  def list_container(container_sas_url \\ @sas_url) when is_binary(container_sas_url) do
    Azurino.BlobCache.list_container()
  end

  def list_container_no_cache(container_sas_url \\ @sas_url) when is_binary(container_sas_url) do
    list_url =
      if String.contains?(container_sas_url, "?") do
        container_sas_url <> "&restype=container&comp=list"
      else
        container_sas_url <> "?restype=container&comp=list"
      end

    case HTTPoison.get(list_url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.debug("Raw Azure Response: #{body}")
        parse_blob_list(body)

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.debug("Raw Azure Response: #{body}")
        {:error, {:http_error, code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.debug("Raw Azure Response: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  def list_folder(folder_path, container_sas_url \\ @sas_url)
      when is_binary(container_sas_url) and is_binary(folder_path) do
    # Normalize folder path
    normalized_folder =
      case String.trim(folder_path) do
        # Root folder - empty prefix
        "" ->
          ""

        # Non-empty folder - ensure trailing slash
        path ->
          if String.ends_with?(path, "/") do
            path
          else
            path <> "/"
          end
      end

    # Build URL - when prefix is empty, we still include it but with empty value
    list_url =
      if String.contains?(container_sas_url, "?") do
        container_sas_url <>
          "&restype=container&comp=list&prefix=" <>
          URI.encode(normalized_folder) <>
          "&delimiter=" <> URI.encode("/")
      else
        container_sas_url <>
          "?restype=container&comp=list&prefix=" <>
          URI.encode(normalized_folder) <>
          "&delimiter=" <> URI.encode("/")
      end

    case HTTPoison.get(list_url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.debug("Raw Azure Response: #{body}")
        parse_blob_list(body)

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.debug("Raw Azure Response: #{body}")
        {:error, {:http_error, code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.debug("Raw Azure Response: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  def upload(container_sas_url, remote_folder, local_file_path)
      when is_binary(container_sas_url) and is_binary(remote_folder) and
             is_binary(local_file_path) do
    # Read the file
    case File.read(local_file_path) do
      {:ok, file_content} ->
        # Extract filename from local path
        filename = Path.basename(local_file_path)

        # Build blob path (remote_folder/filename)
        blob_path =
          if remote_folder == "" or remote_folder == "/" do
            filename
          else
            # Remove trailing slash from folder if present
            folder = String.trim_trailing(remote_folder, "/")
            "#{folder}/#{filename}"
          end

        # Build upload URL
        upload_url = build_blob_url(container_sas_url, blob_path)

        # Upload the file
        headers = [
          {"x-ms-blob-type", "BlockBlob"},
          {"Content-Type", get_content_type(filename)}
        ]

        case HTTPoison.put(upload_url, file_content, headers) do
          {:ok, %HTTPoison.Response{status_code: code}} when code in 200..299 ->
            {:ok, blob_path}

          {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
            {:error, {:http_error, code, body}}

          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, {:request_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Downloads a blob and returns it as a binary.
  """
  def download(container_sas_url, blob_path)
      when is_binary(container_sas_url) and is_binary(blob_path) do
    download_url = build_blob_url(container_sas_url, blob_path)

    case HTTPoison.get(download_url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, {:http_error, code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Downloads a blob as a stream that can be used in Phoenix responses.
  Returns a stream that yields chunks of data.
  """
  def download_stream(container_sas_url, blob_path)
      when is_binary(container_sas_url) and is_binary(blob_path) do
    download_url = build_blob_url(container_sas_url, blob_path)

    # Return a stream that will fetch the data when consumed
    Stream.resource(
      fn ->
        # Start the HTTP request with stream_to option
        case HTTPoison.get(download_url, [], stream_to: self(), async: :once) do
          {:ok, %HTTPoison.AsyncResponse{id: id}} -> {:ok, id}
          {:error, reason} -> {:error, reason}
        end
      end,
      fn
        {:error, reason} ->
          {:halt, {:error, reason}}

        {:ok, id} ->
          receive do
            %HTTPoison.AsyncStatus{id: ^id, code: 200} ->
              HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
              {[], {:ok, id}}

            %HTTPoison.AsyncStatus{id: ^id, code: code} ->
              {:halt, {:error, {:http_error, code}}}

            %HTTPoison.AsyncHeaders{id: ^id} ->
              HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
              {[], {:ok, id}}

            %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
              HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
              {[chunk], {:ok, id}}

            %HTTPoison.AsyncEnd{id: ^id} ->
              {:halt, {:ok, id}}
          after
            5000 -> {:halt, {:error, :timeout}}
          end
      end,
      fn
        {:ok, id} -> :hackney.close(id)
        {:error, _} -> :ok
      end
    )
  end

  @doc """
  Gets metadata about a blob (size, content-type, etc.) without downloading it.
  """
  def get_blob_metadata(container_sas_url, blob_path)
      when is_binary(container_sas_url) and is_binary(blob_path) do
    download_url = build_blob_url(container_sas_url, blob_path)

    case HTTPoison.head(download_url) do
      {:ok, %HTTPoison.Response{status_code: 200, headers: headers}} ->
        metadata = %{
          content_type: get_header(headers, "content-type"),
          content_length: get_header(headers, "content-length") |> parse_integer(),
          last_modified: get_header(headers, "last-modified"),
          etag: get_header(headers, "etag")
        }

        {:ok, metadata}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, {:http_error, code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp get_header(headers, key) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(k) == String.downcase(key), do: v
    end)
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp build_blob_url(container_sas_url, blob_path) do
    # Parse the container URL to extract base URL and SAS token
    case String.split(container_sas_url, "?", parts: 2) do
      [base_url, sas_token] ->
        # Ensure base_url ends with /
        base = String.trim_trailing(base_url, "/")
        "#{base}/#{URI.encode(blob_path)}?#{sas_token}"

      [base_url] ->
        base = String.trim_trailing(base_url, "/")
        "#{base}/#{URI.encode(blob_path)}"
    end
  end

  defp get_content_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".txt" -> "text/plain"
      ".json" -> "application/json"
      ".xml" -> "application/xml"
      ".pdf" -> "application/pdf"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".html" -> "text/html"
      ".css" -> "text/css"
      ".js" -> "application/javascript"
      ".zip" -> "application/zip"
      _ -> "application/octet-stream"
    end
  end

  defp parse_blob_list(xml_body) do
    xml_body =
      case xml_body do
        <<0xEF, 0xBB, 0xBF, rest::binary>> -> rest
        other -> other
      end

    {doc, _} = :xmerl_scan.string(String.to_charlist(xml_body))

    files = extract_blob_names(doc)
    folders = extract_blob_prefix_names(doc)

    {:ok, %{files: files, folders: folders}}
  end

  defp extract_blob_names(doc) do
    :xmerl_xpath.string(~c"//Blob/Name/text()", doc)
    |> Enum.map(fn {:xmlText, _, _, _, blob_name, _} ->
      List.to_string(blob_name)
    end)
  end

  defp extract_blob_prefix_names(doc) do
    :xmerl_xpath.string(~c"//BlobPrefix/Name/text()", doc)
    |> Enum.map(fn {:xmlText, _, _, _, prefix_name, _} ->
      List.to_string(prefix_name)
    end)
  end
end
