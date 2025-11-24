defmodule AzurinoWeb.Api.AzureControllerCachingTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint AzurinoWeb.Endpoint

  # Mock Azure module that doesn't require SAS URL
  defmodule MockAzure do
    def get_blob_metadata("test.txt"), do: get_blob_metadata("test.txt", nil)
    def get_blob_metadata("updated.txt"), do: get_blob_metadata("updated.txt", nil)

    def get_blob_metadata("test.txt", _sas_url) do
      {:ok,
       %{
         content_type: "text/plain",
         content_length: 100,
         last_modified: "Mon, 24 Nov 2025 12:00:00 GMT",
         etag: "\"abc123\""
       }}
    end

    def get_blob_metadata("updated.txt", _sas_url) do
      {:ok,
       %{
         content_type: "text/plain",
         content_length: 120,
         last_modified: "Mon, 24 Nov 2025 13:00:00 GMT",
         etag: "\"xyz789\""
       }}
    end

    def download("test.txt"), do: download("test.txt", nil)
    def download("updated.txt"), do: download("updated.txt", nil)

    def download("test.txt", _sas_url) do
      {:ok, "file content"}
    end

    def download("updated.txt", _sas_url) do
      {:ok, "updated file content"}
    end

    def sas_url, do: ""
  end

  setup do
    original_module = Application.get_env(:azurino, :storage_module)
    Application.put_env(:azurino, :storage_module, MockAzure)

    on_exit(fn ->
      if original_module do
        Application.put_env(:azurino, :storage_module, original_module)
      else
        Application.delete_env(:azurino, :storage_module)
      end
    end)

    :ok
  end

  describe "download_signed with ETag caching" do
    test "returns 304 Not Modified when client has current ETag" do
      signed_params =
        Azurino.SignedURL.sign(
          path: "test.txt",
          expires_in: 3600
        )

      # First request - should download file
      conn1 =
        build_conn()
        |> get("/api/download-signed", signed_params)

      assert conn1.status == 200
      assert get_resp_header(conn1, "etag") == ["\"abc123\""]
      assert get_resp_header(conn1, "last-modified") == ["Mon, 24 Nov 2025 12:00:00 GMT"]
      assert get_resp_header(conn1, "cache-control") == ["private, max-age=3600"]

      # Second request with matching ETag - should return 304
      conn2 =
        build_conn()
        |> put_req_header("if-none-match", "\"abc123\"")
        |> get("/api/download-signed", signed_params)

      assert conn2.status == 304
      assert get_resp_header(conn2, "etag") == ["\"abc123\""]
      assert conn2.resp_body == ""
    end

    test "returns 304 Not Modified when client has current Last-Modified" do
      signed_params =
        Azurino.SignedURL.sign(
          path: "test.txt",
          expires_in: 3600
        )

      # Request with matching Last-Modified - should return 304
      conn =
        build_conn()
        |> put_req_header("if-modified-since", "Mon, 24 Nov 2025 12:00:00 GMT")
        |> get("/api/download-signed", signed_params)

      assert conn.status == 304
      assert get_resp_header(conn, "last-modified") == ["Mon, 24 Nov 2025 12:00:00 GMT"]
      assert conn.resp_body == ""
    end

    test "downloads file when client ETag doesn't match" do
      signed_params =
        Azurino.SignedURL.sign(
          path: "updated.txt",
          expires_in: 3600
        )

      # Request with outdated ETag - should return 200 with new content
      conn =
        build_conn()
        |> put_req_header("if-none-match", "\"abc123\"")
        |> get("/api/download-signed", signed_params)

      assert conn.status == 200
      assert get_resp_header(conn, "etag") == ["\"xyz789\""]
      assert conn.resp_body == "updated file content"
    end
  end
end
