defmodule Mix.Tasks.Azurino.DeleteUser do
  @moduledoc """
  Delete a user from the system.

  ## Usage

      mix azurino.delete_user email@example.com

  ## Examples

      mix azurino.delete_user test@example.com
      mix azurino.delete_user old-user@company.com

  """
  use Mix.Task

  @shortdoc "Delete a user by email"

  @impl Mix.Task
  def run([email]) do
    env = Mix.env()

    if env == :prod do
      Mix.shell().error("Cannot delete users in production environment!")
      Mix.shell().error("Please set MIX_ENV=dev or run this on the production server directly.")
      System.halt(1)
    end

    Mix.Task.run("app.start")

    Mix.shell().info("Deleting user from #{env} environment...")

    case Azurino.Accounts.get_user_by_email(email) do
      nil ->
        Mix.shell().error("User not found: #{email}")

      user ->
        case Azurino.Repo.delete(user) do
          {:ok, deleted_user} ->
            Mix.shell().info("User deleted successfully!")
            Mix.shell().info("Email: #{deleted_user.email}")
            Mix.shell().info("ID: #{deleted_user.id}")

          {:error, changeset} ->
            Mix.shell().error("Failed to delete user:")
            Mix.shell().error(inspect(changeset))
        end
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix azurino.delete_user email@example.com")
  end
end
