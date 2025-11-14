defmodule AzurinoWeb.PageController do
  use AzurinoWeb, :controller

  def home(conn, _params) do
    # text(conn, "Hello!")
    render(conn, :home)
  end
end
