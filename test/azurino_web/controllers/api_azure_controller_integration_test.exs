defmodule AzurinoWeb.Api.AzureControllerIntegrationTest do
  use AzurinoWeb.ConnCase, async: false

  @default_token "token-integration"

  setup do
    previous_tokens = Application.get_env(:azurino, :bucket_tokens)
    previous_storage = Application.get_env(:azurino, :storage_module)

    Application.put_env(:azurino, :bucket_tokens, %{
      "default" => [@default_token],
      "test01" => [@default_token]
    })

    on_exit(fn ->
      if is_nil(previous_tokens) do
        Application.delete_env(:azurino, :bucket_tokens)
      else
        Application.put_env(:azurino, :bucket_tokens, previous_tokens)
      end

      if is_nil(previous_storage) do
        Application.delete_env(:azurino, :storage_module)
      else
        Application.put_env(:azurino, :storage_module, previous_storage)
      end
    end)

    :ok
  end

  describe "integration: health endpoints" do
    test "GET /api/health returns ok without auth", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert json_response(conn, 200) == %{"status" => "ok", "message" => "API is running"}
    end

    test "GET /api/health/:id returns healthy status without auth", %{conn: conn} do
      conn = get(conn, ~p"/api/health/myservice")
      assert json_response(conn, 200)["id"] == "myservice"
      assert json_response(conn, 200)["status"] == "healthy"
    end
  end

  describe "integration: authentication" do
    test "GET /api/azure/:bucket/exists requires auth token", %{conn: conn} do
      conn = get(conn, ~p"/api/azure/default/exists?filename=test.txt")
      assert json_response(conn, 401)["error"] == "Missing Authorization header"
    end

    test "GET /api/azure/:bucket/exists rejects invalid bucket token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-token")
        |> get(~p"/api/azure/default/exists?filename=test.txt")

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end
  end

  describe "integration: exists endpoint" do
    test "GET /api/azure/:bucket/exists with valid token and query param", %{conn: conn} do
      defmodule TestMockExistsIntegration do
        def get_blob_metadata(_filename, _bucket) do
          {:ok,
           %{
             content_type: "text/plain",
             content_length: 100,
             last_modified: "Mon, 01 Jan 2024 00:00:00 GMT",
             etag: "abc123"
           }}
        end
      end

      Application.put_env(:azurino, :storage_module, TestMockExistsIntegration)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> get(~p"/api/azure/test01/exists?filename=test.txt")

      assert json_response(conn, 200)["exists"] == true
      assert json_response(conn, 200)["filename"] == "test.txt"
    end

    test "GET /api/azure/:bucket/exists with filename containing slashes", %{conn: conn} do
      defmodule TestMockExistsSlashes do
        def get_blob_metadata("folder/subfolder/file.txt", "test01") do
          {:ok,
           %{
             content_type: "text/plain",
             content_length: 100,
             last_modified: "Mon, 01 Jan 2024 00:00:00 GMT",
             etag: "abc123"
           }}
        end

        def get_blob_metadata(_filename, _bucket), do: {:error, :not_found}
      end

      Application.put_env(:azurino, :storage_module, TestMockExistsSlashes)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> get(~p"/api/azure/test01/exists?filename=folder/subfolder/file.txt")

      assert json_response(conn, 200)["exists"] == true
      assert json_response(conn, 200)["filename"] == "folder/subfolder/file.txt"
    end
  end

  describe "integration: info endpoint" do
    test "GET /api/azure/:bucket/info returns file metadata", %{conn: conn} do
      defmodule TestMockInfoIntegration do
        def get_blob_metadata(_filename, _bucket) do
          {:ok,
           %{
             content_type: "application/pdf",
             content_length: 2048,
             last_modified: "Tue, 02 Jan 2024 12:00:00 GMT",
             etag: "xyz789"
           }}
        end
      end

      Application.put_env(:azurino, :storage_module, TestMockInfoIntegration)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> get(~p"/api/azure/test01/info?filename=document.pdf")

      response = json_response(conn, 200)
      assert response["filename"] == "document.pdf"
      assert response["size"] == 2048
      assert response["content_type"] == "application/pdf"
      assert response["etag"] == "xyz789"
    end

    test "GET /api/azure/:bucket/info returns 404 when file not found", %{conn: conn} do
      defmodule TestMockInfoNotFoundIntegration do
        def get_blob_metadata(_filename, _bucket), do: {:error, :not_found}
      end

      Application.put_env(:azurino, :storage_module, TestMockInfoNotFoundIntegration)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> get(~p"/api/azure/test01/info?filename=missing.txt")

      assert json_response(conn, 404)["status"] == "error"
      assert json_response(conn, 404)["message"] == "File not found"
    end
  end

  describe "integration: delete endpoint" do
    test "DELETE /api/azure/:bucket/delete removes file", %{conn: conn} do
      defmodule TestMockDeleteIntegration do
        def delete(_filename, _bucket), do: {:ok, "path/to/deleted/file"}
      end

      Application.put_env(:azurino, :storage_module, TestMockDeleteIntegration)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> delete(~p"/api/azure/test01/delete?filename=oldfile.txt")

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["filename"] == "oldfile.txt"
      assert response["message"] == "File deleted"
    end

    test "DELETE /api/azure/:bucket/delete with path-like filename", %{conn: conn} do
      defmodule TestMockDeletePathIntegration do
        def delete("reports/2024/summary.pdf", "test01"), do: {:ok, "reports/2024/summary.pdf"}
        def delete(_filename, _bucket), do: {:error, :not_found}
      end

      Application.put_env(:azurino, :storage_module, TestMockDeletePathIntegration)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> delete(~p"/api/azure/test01/delete?filename=reports/2024/summary.pdf")

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["filename"] == "reports/2024/summary.pdf"
    end
  end

  describe "integration: list endpoint" do
    test "GET /api/azure/:bucket/list returns files and folders", %{conn: conn} do
      defmodule TestMockListIntegration do
        def list_folder(_folder, _bucket) do
          {:ok,
           %{
             files: [
               %{name: "report.pdf", size: 1024, modified: "2024-01-01"}
             ],
             folders: [
               %{name: "archives"}
             ]
           }}
        end
      end

      Application.put_env(:azurino, :storage_module, TestMockListIntegration)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> get(~p"/api/azure/test01/list?folder=documents")

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert length(response["files"]) == 1
      assert length(response["folders"]) == 1
      assert Enum.at(response["files"], 0)["name"] == "report.pdf"
    end

    test "GET /api/azure/:bucket/list without folder param lists root", %{conn: conn} do
      defmodule TestMockListRootIntegration do
        def list_folder("", _bucket) do
          {:ok, %{files: [%{name: "root.txt"}], folders: []}}
        end

        def list_folder(_folder, _bucket) do
          {:ok, %{files: [], folders: []}}
        end
      end

      Application.put_env(:azurino, :storage_module, TestMockListRootIntegration)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> get(~p"/api/azure/test01/list")

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert Enum.at(response["files"], 0)["name"] == "root.txt"
    end
  end

  describe "integration: download endpoint" do
    test "GET /api/azure/:bucket/download returns signed URL params", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> get(~p"/api/azure/test01/download?filename=data.csv")

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["filename"] == "data.csv"
      assert response["signed_url"]["path"] == "data.csv"
      assert response["signed_url"]["signature"]
      assert response["signed_url"]["expires"]
    end
  end

  describe "integration: upload endpoint" do
    test "POST /api/azure/:bucket/upload with file", %{conn: conn} do
      defmodule TestMockUploadIntegration do
        def upload(_bucket, _folder, _path, filename), do: {:ok, "uploads/#{filename}"}
      end

      Application.put_env(:azurino, :storage_module, TestMockUploadIntegration)

      upload = %Plug.Upload{
        path: "test/fixtures/test_upload.txt",
        filename: "integration_test.txt",
        content_type: "text/plain"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> post(~p"/api/azure/test01/upload", %{"file" => upload, "folder" => "uploads"})

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["filename"] == "integration_test.txt"
      assert response["blob_path"] == "uploads/integration_test.txt"
      assert response["signed_url"]["path"] == "uploads/integration_test.txt"
    end
  end
end
