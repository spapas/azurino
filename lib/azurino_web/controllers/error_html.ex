defmodule AzurinoWeb.ErrorHTML do
  use AzurinoWeb, :html

  @moduledoc """
  Minimal error HTML renderer used by Endpoint.render_errors in tests.
  Provides simple responses for 404 and 500 templates and a fallback.
  """

  def render("404.html", _assigns) do
    "<html><body><h1>404 Not Found</h1></body></html>"
  end

  def render("500.html", _assigns) do
    "<html><body><h1>500 Internal Server Error</h1></body></html>"
  end

  def render(_template, _assigns) do
    "<html><body><h1>Internal Server Error</h1></body></html>"
  end

  def template_not_found(template, assigns), do: render(template, assigns)
end
