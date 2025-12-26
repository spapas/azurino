defmodule Azurino.Azure do
  require Logger
  @moduledoc "List Azure container blobs via SAS URL"

  @default_timeout 30_000
  @stream_timeout 5_000

  defp get_sas_url(bucket_name) do
    case Application.get_env(:azurino, :buckets) do
      nil ->
        Logger.error("Azurino :buckets configuration is missing.")
        nil
      buckets_map when is_map(buckets_map) ->
        Map.get(buckets_map, bucket_name)
      _ ->
        Logger.error("Azurino :buckets configuration is not a map.")
        nil
    end
  end

  def sas_url(bucket_name \\ "default"), do: get_sas_url(bucket_name)

  def list_container(bucket_name \\ "default") do
    Azurino.BlobCache.list_container(bucket_name)
  end

  def list_container_no_cache(bucket_name \\ "default") do
    sas_url = get_sas_url(bucket_name)

    list_url =
      if String.contains?(sas_url, "?") do
        sas_url <> "&restype=container&comp=list"
      else
        sas_url <> "?restype=container&comp=list"
      end

    {usec, resp} = :timer.tc(fn -> Req.get(list_url, receive_timeout: @default_timeout) end)
    ms = usec / 1000
    Logger.info("Azure list_container_no_cache: url=#{list_url} elapsed_ms=#{ms}")
    handle_response(resp, &parse_blob_list/1)
  end

  def list_folder(folder_path \\ "", bucket_name \\ "default")
      when is_binary(folder_path) do
    sas_url = get_sas_url(bucket_name)

    # If no SAS/container URL is configured, return empty listing instead of failing
    if is_nil(sas_url) or sas_url == "" do
      {:ok, %{files: [], folders: []}}
    else
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

      {usec, resp} = :timer.tc(fn -> Req.get(list_url, receive_timeout: @default_timeout) end)
      ms = usec / 1000
      Logger.info("Azure list_folder: folder=#{normalized_folder} url=#{list_url} elapsed_ms=#{ms}")
      handle_response(resp, &parse_blob_list/1)
    end
  end

    def upload(bucket_name \\ "default", remote_folder, local_file_path, original_filename \\ nil)
      when is_binary(remote_folder) and is_binary(local_file_path) do
    sas_url = get_sas_url(bucket_name)

    # Read the file
    case File.read(local_file_path) do
      {:ok, file_content} ->
        # Determine filename: prefer provided original filename (from Plug.Upload),
        # otherwise fall back to the local path basename
        filename = original_filename || Path.basename(local_file_path)

        # Normalize folder
        folder =
          if remote_folder in ["", "/"], do: "", else: String.trim_trailing(remote_folder, "/")

        # Ensure unique filename if file already exists in container/folder
          unique_filename = make_unique_filename(bucket_name, folder, filename)

        # Build blob path (remote_folder/filename)
        blob_path = if folder == "", do: unique_filename, else: "#{folder}/#{unique_filename}"

        # Build upload URL
          upload_url = build_blob_url(sas_url, blob_path)

        # Upload the file
        headers = [
          {"x-ms-blob-type", "BlockBlob"},
          {"content-type", get_content_type(unique_filename)}
        ]

        {usec, put_res} = :timer.tc(fn ->
          Req.put(upload_url,
            body: file_content,
            headers: headers,
            receive_timeout: @default_timeout
          )
        end)
        put_ms = usec / 1000
        Logger.info("Azure upload: url=#{upload_url} filename=#{unique_filename} elapsed_ms=#{put_ms}")

        case put_res do
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

  @doc false
  # Public wrapper to make testing easier. Returns the filename to use
  # If `exists_fun` is provided, it will be called as `exists_fun.(sas_url, blob_path)`
  # to determine whether a blob exists. Defaults to internal `exists_in_container?/2`.
    def make_unique_filename(
          bucket_name \\ "default",
          folder,
          filename,
          exists_fun \\ &exists_in_container?/2,
          max_attempts \\ 5
        ) do
    base = Path.rootname(filename)
    ext = Path.extname(filename)

    try_generate_unique(bucket_name, folder, base, ext, exists_fun, max_attempts, 0)
  end

  defp try_generate_unique(_bucket_name, folder, base, ext, _exists_fun, _max, _attempt)
       when folder == nil do
    # fallback
    "#{base}#{ext}"
  end

  defp try_generate_unique(bucket_name, folder, base, ext, exists_fun, max_attempts, attempt)
       when attempt == 0 do
    candidate = "#{base}#{ext}"
    blob_path = if(folder == "", do: candidate, else: "#{folder}/#{candidate}")

    case exists_fun.(bucket_name, blob_path) do
      false ->
        candidate

      true ->
        if max_attempts <= 1 do
          # single attempt only -> fallback to timestamp
          timestamp_fallback(base, ext)
        else
          try_generate_unique(bucket_name, folder, base, ext, exists_fun, max_attempts, 1)
        end
    end
  end

  defp try_generate_unique(bucket_name, folder, base, ext, exists_fun, max_attempts, attempt)
       when attempt > 0 and attempt < max_attempts do
    rand = random_string(10)
    candidate = "#{base}.#{rand}#{ext}"
    blob_path = if(folder == "", do: candidate, else: "#{folder}/#{candidate}")

    case exists_fun.(bucket_name, blob_path) do
      false ->
        candidate

      true ->
        try_generate_unique(bucket_name, folder, base, ext, exists_fun, max_attempts, attempt + 1)
    end
  end

  defp try_generate_unique(_bucket_name, _folder, base, ext, _exists_fun, _max_attempts, _attempt) do
    # Exhausted attempts -> use timestamp fallback
    timestamp_fallback(base, ext)
  end

  defp timestamp_fallback(base, ext) do
    ts = System.system_time(:second)
    "#{base}.#{ts}#{ext}"
  end

  defp exists_in_container?(bucket_name, blob_path) do
    case get_blob_metadata(blob_path, bucket_name) do
      {:ok, _} -> true
      {:error, :not_found} -> false
      _ -> false
    end
  end

  defp random_string(len) when is_integer(len) and len > 0 do
    :crypto.strong_rand_bytes(len)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, len)
  end

  @doc """
  Deletes a blob from Azure storage.
  """
  def delete(blob_path, bucket_name \\ "default")
      when is_binary(blob_path) do
    sas_url = get_sas_url(bucket_name)
      delete_url = build_blob_url(sas_url, blob_path)

    {usec, del_res} = :timer.tc(fn -> Req.delete(delete_url, receive_timeout: @default_timeout) end)
    del_ms = usec / 1000
    Logger.info("Azure delete: url=#{delete_url} elapsed_ms=#{del_ms}")

    case del_res do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:ok, blob_path}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Downloads a blob and returns it as a binary.
  """
  def download(blob_path, bucket_name \\ "default")
      when is_binary(blob_path) do
    sas_url = get_sas_url(bucket_name)
      download_url = build_blob_url(sas_url, blob_path)

    {usec, get_res} = :timer.tc(fn -> Req.get(download_url, receive_timeout: @default_timeout) end)
    get_ms = usec / 1000
    Logger.info("Azure download: url=#{download_url} elapsed_ms=#{get_ms}")

    case get_res do
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
  def download_stream(blob_path, bucket_name \\ "default")
      when is_binary(blob_path) do
    sas_url = get_sas_url(bucket_name)
      download_url = build_blob_url(sas_url, blob_path)

    # Req supports streaming via into: option
    Stream.resource(
      fn -> nil end,
      fn acc ->
        case acc do
          nil ->
            {usec, stream_res} = :timer.tc(fn -> Req.get(download_url, into: :self, receive_timeout: @stream_timeout) end)
            stream_ms = usec / 1000
            Logger.info("Azure download_stream: url=#{download_url} elapsed_ms=#{stream_ms}")

            case stream_res do
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
  def get_blob_metadata(blob_path, bucket_name \\ "default")
      when is_binary(blob_path) do
    sas_url = get_sas_url(bucket_name)
      download_url = build_blob_url(sas_url, blob_path)

    {usec, head_res} = :timer.tc(fn -> Req.head(download_url, receive_timeout: @default_timeout) end)
    head_ms = usec / 1000
    Logger.info("Azure head (metadata): url=#{download_url} elapsed_ms=#{head_ms}")

    case head_res do
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

    defp build_blob_url(sas_url, blob_path) do
    # Parse the container URL to extract base URL and SAS token
      case String.split(sas_url, "?", parts: 2) do
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
    Logger.debug("Raw Azure Response (200) body_size=#{byte_size(body)}")
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

      {usec, result} = :timer.tc(fn ->
        {doc, _} = :xmerl_scan.string(String.to_charlist(xml_body))
        files = extract_blob_names(doc)
        folders = extract_blob_prefix_names(doc)
        {:ok, %{files: files, folders: folders}}
      end)

      Logger.info("parse_blob_list elapsed_ms=#{usec / 1000}")
      result
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
