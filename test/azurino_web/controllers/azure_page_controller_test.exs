defmodule AzurinoWeb.AzurePageControllerTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest

  alias AzurinoWeb.AzurePageController

  test "azure page upload redirects back to folder on success" do
    mock = Module.concat([TestMockStorageAzurePage])

    defmodule mock do
      def upload(_sas, folder, _path, filename),
        do: {:ok, if(folder == "", do: filename, else: "#{folder}/#{filename}")}

      def delete(_filename, _bucket), do: {:ok, "deleted"}
    end

    previous_storage = Application.get_env(:azurino, :storage_module)
    Application.put_env(:azurino, :storage_module, mock)
    on_exit(fn ->
      if is_nil(previous_storage) do
        Application.delete_env(:azurino, :storage_module)
      else
        Application.put_env(:azurino, :storage_module, previous_storage)
      end
    end)

    # create a temporary file to simulate upload
    tmp = Path.join(System.tmp_dir!(), "test_upload.txt")
    File.write!(tmp, "hello")

    upload = %Plug.Upload{path: tmp, filename: "sync-time.bat", content_type: "text/plain"}

    conn =
      build_conn()
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()
      |> Plug.Parsers.call(Plug.Parsers.init(parsers: []))

    conn = AzurePageController.upload(conn, %{"path" => "myfolder", "file" => upload})

    # controller redirects back to /azure?path=myfolder
    assert conn.status in [302, 303]
    assert Enum.any?(conn.resp_headers, fn {k, _v} -> k == "location" end)
  end
end
