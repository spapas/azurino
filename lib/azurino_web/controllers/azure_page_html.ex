defmodule AzurinoWeb.AzurePageHTML do
  use AzurinoWeb, :html

  embed_templates "azure_page_html/*"

  @doc """
  Formats bytes into human-readable format (KB, MB, GB)
  """
  def format_bytes(nil), do: ""
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  def format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end
