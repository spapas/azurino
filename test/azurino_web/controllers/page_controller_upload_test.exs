defmodule AzurinoWeb.PageControllerUploadTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest

  alias AzurinoWeb.PageController

  test "page upload redirects back to folder on success" do
    mock = Module.concat([TestMockStoragePage])

    defmodule mock do
      def upload(_sas, folder, _path, filename),
        do: {:ok, if(folder == "", do: filename, else: "#{folder}/#{filename}")}
    end

    Application.put_env(:azurino, :storage_module, mock)

    # create a temporary file to simulate upload
    tmp = Path.join(System.tmp_dir!(), "test_upload.txt")
    File.write!(tmp, "hello")

    upload = %Plug.Upload{path: tmp, filename: "sync-time.bat", content_type: "text/plain"}

    conn = build_conn() |> init_test_session(%{}) |> Phoenix.Controller.fetch_flash()

    conn = PageController.upload(conn, %{"path" => "myfolder", "file" => upload})

    # controller redirects back to /?path=myfolder
    assert conn.status in [302, 303]
    assert Enum.any?(conn.resp_headers, fn {k, _v} -> k == "location" end)
  end
end
