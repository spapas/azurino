defmodule AzurinoWeb.PageController do
  use AzurinoWeb, :controller

  def home(conn, _params) do
    # {:ok, contents} = Azurino.Azure.list_container()
    # {:ok, contents} = Azurino.Azure.folders("")
    {:ok, %{files: files, folders: contents}} = Azurino.Azure.list_folder("test1")
    render(conn, :home, %{files: files, folders: contents})
  end
end
