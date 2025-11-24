defmodule AzurinoWeb.PageController do
  use AzurinoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
