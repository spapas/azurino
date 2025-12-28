defmodule AzurinoWeb.Api.AzureControllerTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn

  alias AzurinoWeb.Api.AzureController
  alias AzurinoWeb.Plugs.ApiAuth

  @default_token "token-default"

  setup do
    previous_tokens = Application.get_env(:azurino, :bucket_tokens)

    Application.put_env(:azurino, :bucket_tokens, %{
      "default" => [@default_token, "token-multi"],
      "test01" => ["token-multi"]
    })

    on_exit(fn ->
      if is_nil(previous_tokens) do
        Application.delete_env(:azurino, :bucket_tokens)
      else
        Application.put_env(:azurino, :bucket_tokens, previous_tokens)
      end
    end)

    :ok
  end

  describe "api auth plug" do
    test "rejects missing token" do
      conn =
        build_conn()
        |> Map.put(:path_params, %{"bucket" => "default"})
        |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 401
      assert %{"error" => "Missing Authorization header"} = Jason.decode!(conn.resp_body)
    end

    test "rejects token without bucket access" do
      conn =
        build_conn()
        |> Map.put(:path_params, %{"bucket" => "private-bucket"})
        |> put_req_header("authorization", "Bearer #{@default_token}")
        |> ApiAuth.call([])

      assert conn.halted
      assert conn.status == 403
      assert %{"error" => "Token not allowed for bucket"} = Jason.decode!(conn.resp_body)
    end

    test "allows token with bucket access" do
      conn =
        build_conn()
        |> Map.put(:path_params, %{"bucket" => "test01"})
        |> put_req_header("authorization", "Bearer token-multi")
        |> ApiAuth.call([])

      refute conn.halted
    end
  end

  test "upload returns blob url and path" do
    # Define a mock storage module for the test
    mock = Module.concat([TestMockStorageApi])

    defmodule mock do
      def upload(_sas, _folder, _path, _filename), do: {:ok, "myfolder/sync-time.bat"}
    end

    Application.put_env(:azurino, :storage_module, mock)

    conn = authed_conn()

    upload = %Plug.Upload{path: "tmp/fake", filename: "sync-time.bat", content_type: "text/plain"}

    conn = AzureController.upload(conn, %{"file" => upload, "folder" => "myfolder", "bucket" => "default"})

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "success"
    assert body["blob_path"] == "myfolder/sync-time.bat"
    # Check that signed_url is present and contains path
    assert body["signed_url"]["path"] == "myfolder/sync-time.bat"
    assert body["signed_url"]["signature"]
    assert body["signed_url"]["expires"]
  end

  describe "delete" do
    test "deletes file successfully" do
      defmodule TestMockDelete do
        def delete(_filename, _bucket), do: {:ok, "path/to/deleted/file"}
      end

      Application.put_env(:azurino, :storage_module, TestMockDelete)

      conn = authed_conn()
      conn = AzureController.delete(conn, %{"filename" => "test.txt", "bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "success"
      assert body["filename"] == "test.txt"
      assert body["message"] == "File deleted"
    end

    test "returns 404 when file not found" do
      defmodule TestMockDeleteNotFound do
        def delete(_filename, _bucket), do: {:error, :not_found}
      end

      Application.put_env(:azurino, :storage_module, TestMockDeleteNotFound)

      conn = authed_conn()
      conn = AzureController.delete(conn, %{"filename" => "missing.txt", "bucket" => "default"})

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
      assert body["message"] == "File not found"
    end

    test "returns 500 on HTTP error" do
      defmodule TestMockDeleteHttpError do
        def delete(_filename, _bucket), do: {:error, {:http_error, 500, "Server error"}}
      end

      Application.put_env(:azurino, :storage_module, TestMockDeleteHttpError)

      conn = authed_conn()
      conn = AzureController.delete(conn, %{"filename" => "test.txt", "bucket" => "default"})

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
    end
  end

  describe "exists" do
    test "returns true when file exists" do
      defmodule TestMockExists do
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

      Application.put_env(:azurino, :storage_module, TestMockExists)

      conn = authed_conn()
      conn = AzureController.exists(conn, %{"filename" => "test.txt", "bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["exists"] == true
      assert body["filename"] == "test.txt"
    end

    test "returns false when file not found" do
      defmodule TestMockExistsNotFound do
        def get_blob_metadata(_filename, _bucket), do: {:error, :not_found}
      end

      Application.put_env(:azurino, :storage_module, TestMockExistsNotFound)

      conn = authed_conn()
      conn = AzureController.exists(conn, %{"filename" => "missing.txt", "bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["exists"] == false
      assert body["filename"] == "missing.txt"
    end

    test "returns false on error" do
      defmodule TestMockExistsError do
        def get_blob_metadata(_filename, _bucket), do: {:error, :unknown}
      end

      Application.put_env(:azurino, :storage_module, TestMockExistsError)

      conn = authed_conn()
      conn = AzureController.exists(conn, %{"filename" => "test.txt", "bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["exists"] == false
    end
  end

  describe "info" do
    test "returns file metadata successfully" do
      defmodule TestMockInfo do
        def get_blob_metadata(_filename, _bucket) do
          {:ok,
           %{
             content_type: "text/plain",
             content_length: 1024,
             last_modified: "Mon, 01 Jan 2024 12:00:00 GMT",
             etag: "abc123"
           }}
        end
      end

      Application.put_env(:azurino, :storage_module, TestMockInfo)

      conn = authed_conn()
      conn = AzureController.info(conn, %{"filename" => "test.txt", "bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["filename"] == "test.txt"
      assert body["size"] == 1024
      assert body["content_type"] == "text/plain"
      assert body["last_modified"] == "Mon, 01 Jan 2024 12:00:00 GMT"
      assert body["etag"] == "abc123"
    end

    test "returns 404 when file not found" do
      defmodule TestMockInfoNotFound do
        def get_blob_metadata(_filename, _bucket), do: {:error, :not_found}
      end

      Application.put_env(:azurino, :storage_module, TestMockInfoNotFound)

      conn = authed_conn()
      conn = AzureController.info(conn, %{"filename" => "missing.txt", "bucket" => "default"})

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
      assert body["message"] == "File not found"
    end

    test "returns 500 on error" do
      defmodule TestMockInfoError do
        def get_blob_metadata(_filename, _bucket), do: {:error, :unknown_error}
      end

      Application.put_env(:azurino, :storage_module, TestMockInfoError)

      conn = authed_conn()
      conn = AzureController.info(conn, %{"filename" => "test.txt", "bucket" => "default"})

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
    end
  end

  describe "list" do
    test "lists files and folders successfully" do
      defmodule TestMockListSuccess do
        def list_folder(_folder, _bucket) do
          {:ok,
           %{
             files: [
               %{name: "file1.txt", size: 1024, modified: "2024-01-01"},
               %{name: "file2.pdf", size: 2048, modified: "2024-01-02"}
             ],
             folders: [
               %{name: "subfolder1"},
               %{name: "subfolder2"}
             ]
           }}
        end
      end

      Application.put_env(:azurino, :storage_module, TestMockListSuccess)

      conn = authed_conn()
      conn = AzureController.list(conn, %{"folder" => "myfolder", "bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "success"
      assert length(body["files"]) == 2
      assert length(body["folders"]) == 2
      assert Enum.at(body["files"], 0)["name"] == "file1.txt"
      assert Enum.at(body["folders"], 0)["name"] == "subfolder1"
    end

    test "lists empty directory" do
      defmodule TestMockListEmpty do
        def list_folder(_folder, _bucket) do
          {:ok, %{files: [], folders: []}}
        end
      end

      Application.put_env(:azurino, :storage_module, TestMockListEmpty)

      conn = authed_conn()
      conn = AzureController.list(conn, %{"folder" => "empty", "bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "success"
      assert body["files"] == []
      assert body["folders"] == []
    end

    test "returns 500 on error" do
      defmodule TestMockListError do
        def list_folder(_folder, _bucket), do: {:error, :access_denied}
      end

      Application.put_env(:azurino, :storage_module, TestMockListError)

      conn = authed_conn()
      conn = AzureController.list(conn, %{"folder" => "restricted", "bucket" => "default"})

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "error"
    end

    test "defaults to empty folder when not specified" do
      defmodule TestMockListDefault do
        def list_folder(_folder, _bucket) do
          {:ok, %{files: [%{name: "root.txt"}], folders: []}}
        end
      end

      Application.put_env(:azurino, :storage_module, TestMockListDefault)

      conn = authed_conn()
      conn = AzureController.list(conn, %{"bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "success"
    end
  end

  defp authed_conn(bucket \\ "default", token \\ @default_token) do
    build_conn()
    |> Map.put(:path_params, %{"bucket" => bucket})
    |> put_req_header("authorization", "Bearer " <> token)
    |> ApiAuth.call([])
  end
end
