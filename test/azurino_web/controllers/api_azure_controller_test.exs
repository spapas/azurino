defmodule AzurinoWeb.Api.AzureControllerTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest

  alias AzurinoWeb.Api.AzureController

  test "upload returns blob url and path" do
    # Define a mock storage module for the test
    mock = Module.concat([TestMockStorageApi])

    defmodule mock do
      def upload(_sas, _folder, _path, _filename), do: {:ok, "myfolder/sync-time.bat"}
    end

    Application.put_env(:azurino, :storage_module, mock)

    conn = build_conn()

    upload = %Plug.Upload{path: "tmp/fake", filename: "sync-time.bat", content_type: "text/plain"}

    conn = AzureController.upload(conn, %{"file" => upload, "folder" => "myfolder"})

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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
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

      conn = build_conn()
      conn = AzureController.list(conn, %{"bucket" => "default"})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "success"
    end
  end
end
