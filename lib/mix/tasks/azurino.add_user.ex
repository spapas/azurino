defmodule Mix.Tasks.Azurino.AddUser do
  @moduledoc """
  Add a user to the system.

  ## Usage

      mix azurino.add_user email@example.com

  ## Examples

      mix azurino.add_user admin@example.com
      mix azurino.add_user user@company.com

  """
  use Mix.Task

  @shortdoc "Add a user by email"

  @impl Mix.Task
  def run([email]) do
    env = Mix.env()

    if env == :prod do
      Mix.shell().error("Cannot add users in production environment!")
      Mix.shell().error("Please set MIX_ENV=dev or run this on the production server directly.")
      System.halt(1)
    end

    Mix.Task.run("app.start")

    Mix.shell().info("Adding user to #{env} environment...")

    case Azurino.Accounts.register_user(%{email: email}) do
      {:ok, user} ->
        Mix.shell().info("User created successfully!")
        Mix.shell().info("Email: #{user.email}")
        Mix.shell().info("ID: #{user.id}")
        Mix.shell().info("Environment: #{env}")

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.shell().error("Failed to create user:")

        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)
        |> Enum.each(fn {field, errors} ->
          Mix.shell().error("  #{field}: #{Enum.join(errors, ", ")}")
        end)

        Mix.shell().error("\nUser creation failed!")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix azurino.add_user email@example.com")
  end
end
