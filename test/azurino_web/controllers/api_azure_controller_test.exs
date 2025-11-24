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
end
