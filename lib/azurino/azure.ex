defmodule Azurino.Azure do
  require Logger
  @moduledoc "List Azure container blobs via SAS URL"

  @default_timeout 30_000
  @stream_timeout 5_000

  defp get_sas_url do
    Application.get_env(:azurino, :sas_url)
  end

  def sas_url, do: get_sas_url()

  def list_container(_container_sas_url \\ nil) do
    Azurino.BlobCache.list_container()
  end

  def list_container_no_cache(container_sas_url \\ nil) do
    sas_url = container_sas_url || get_sas_url()

    list_url =
      if String.contains?(sas_url, "?") do
        sas_url <> "&restype=container&comp=list"
      else
        sas_url <> "?restype=container&comp=list"
      end

    list_url
    |> Req.get(receive_timeout: @default_timeout)
    |> handle_response(&parse_blob_list/1)
  end

  def list_folder(folder_path \\ "", container_sas_url \\ nil)
      when is_binary(folder_path) do
    sas_url = container_sas_url || get_sas_url()

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
      if String.contains?(sas_url, "?") do
        sas_url <>
          "&restype=container&comp=list&prefix=" <>
          URI.encode(normalized_folder) <>
          "&delimiter=" <> URI.encode("/")
      else
        sas_url <>
          "?restype=container&comp=list&prefix=" <>
          URI.encode(normalized_folder) <>
          "&delimiter=" <> URI.encode("/")
      end

    list_url
    |> Req.get(receive_timeout: @default_timeout)
    |> handle_response(&parse_blob_list/1)
  end

  def upload(container_sas_url, remote_folder, local_file_path)
      when is_binary(remote_folder) and is_binary(local_file_path) do
    sas_url = container_sas_url || get_sas_url()

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
        upload_url = build_blob_url(sas_url, blob_path)

        # Upload the file
        headers = [
          {"x-ms-blob-type", "BlockBlob"},
          {"content-type", get_content_type(filename)}
        ]

        case Req.put(upload_url, body: file_content, headers: headers, receive_timeout: @default_timeout) do
          {:ok, %Req.Response{status: status}} when status in 200..299 ->
            {:ok, blob_path}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:http_error, status, body}}

          {:error, reason} ->
            {:error, {:request_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Downloads a blob and returns it as a binary.
  """
  def download(blob_path, container_sas_url \\ nil)
      when is_binary(blob_path) do
    sas_url = container_sas_url || get_sas_url()
    download_url = build_blob_url(sas_url, blob_path)

    case Req.get(download_url, receive_timeout: @default_timeout) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Downloads a blob as a stream that can be used in Phoenix responses.
  Returns a stream that yields chunks of data.
  """
  def download_stream(blob_path, container_sas_url \\ nil)
      when is_binary(blob_path) do
    sas_url = container_sas_url || get_sas_url()
    download_url = build_blob_url(sas_url, blob_path)

    # Req supports streaming via into: option
    Stream.resource(
      fn -> nil end,
      fn acc ->
        case acc do
          nil ->
            case Req.get(download_url, into: :self, receive_timeout: @stream_timeout) do
              {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
                {[body], :done}

              {:ok, %Req.Response{status: 404}} ->
                {:halt, {:error, :not_found}}

              {:ok, %Req.Response{status: status}} ->
                {:halt, {:error, {:http_error, status}}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end

          :done ->
            {:halt, :done}
        end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Gets metadata about a blob (size, content-type, etc.) without downloading it.
  """
  def get_blob_metadata(blob_path, container_sas_url \\ nil)
      when is_binary(blob_path) do
    sas_url = container_sas_url || get_sas_url()
    download_url = build_blob_url(sas_url, blob_path)

    case Req.head(download_url, receive_timeout: @default_timeout) do
      {:ok, %Req.Response{status: 200, headers: headers}} ->
        metadata = %{
          content_type: get_header(headers, "content-type"),
          content_length: get_header(headers, "content-length") |> parse_integer(),
          last_modified: get_header(headers, "last-modified"),
          etag: get_header(headers, "etag")
        }

        {:ok, metadata}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp get_header(headers, key) do
    case Enum.find_value(headers, fn {k, v} ->
           if String.downcase(k) == String.downcase(key), do: v
         end) do
      [value | _] when is_binary(value) -> value
      value when is_binary(value) -> value
      _ -> nil
    end
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
    MIME.from_path(filename)
  end

  # Common HTTP response handler
  defp handle_response({:ok, %Req.Response{status: 200, body: body}}, parser_fn) do
    Logger.debug("Raw Azure Response: #{inspect(body)}")
    parser_fn.(body)
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}, _parser_fn) do
    Logger.debug("Raw Azure Response: #{inspect(body)}")
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}, _parser_fn) do
    Logger.debug("Raw Azure Response: #{inspect(reason)}")
    {:error, {:request_failed, reason}}
  end

  defp parse_blob_list(xml_body) do
    try do
      xml_body =
        case xml_body do
          <<0xEF, 0xBB, 0xBF, rest::binary>> -> rest
          other -> other
        end

      {doc, _} = :xmerl_scan.string(String.to_charlist(xml_body))

      files = extract_blob_names(doc)
      folders = extract_blob_prefix_names(doc)

      {:ok, %{files: files, folders: folders}}
    rescue
      e ->
        Logger.error("Failed to parse XML response: #{inspect(e)}")
        {:error, {:xml_parse_error, e}}
    end
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
