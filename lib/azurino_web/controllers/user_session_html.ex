defmodule AzurinoWeb.UserSessionHTML do
  use AzurinoWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:azurino, Azurino.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
