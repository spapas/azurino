defmodule AzurinoWeb.Api.AzureController do
  use AzurinoWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok", message: "API is running"})
  end

  def show(conn, %{"id" => id}) do
    json(conn, %{id: id, status: "healthy"})
  end
end
