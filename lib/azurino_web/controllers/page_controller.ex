defmodule AzurinoWeb.PageController do
  use AzurinoWeb, :controller

  def home(conn, %{"path" => path}) do
    {:ok, %{files: files, folders: contents}} = Azurino.Azure.list_folder(path)
    render(conn, :home, %{files: files, folders: contents})
  end

  def home(conn, _params) do
    home(conn, %{"path" => ""})
  end

  def metadata(conn, %{"path" => path}) do
    case Azurino.Azure.get_blob_metadata(path) do
      {:ok, metadata} ->
        json(conn, metadata)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end
end
