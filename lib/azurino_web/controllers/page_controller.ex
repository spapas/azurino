defmodule AzurinoWeb.PageController do
  use AzurinoWeb, :controller

  def home(conn, _params) do
    text(conn, "From messenger ")
  end
end