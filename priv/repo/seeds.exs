# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Azurino.Repo.insert!(%Azurino.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# set SEED_ADMIN_EMAIL=admin@example.com
# mix run priv/repo/seeds.exs

alias Azurino.Accounts
alias Azurino.Accounts.User

email = System.get_env("SEED_ADMIN_EMAIL") || "admin@example.com"

user =
  case Accounts.get_user_by_email(email) do
    nil ->
      case Accounts.register_user(%{email: email}) do
        {:ok, %User{} = user} ->
          user

        {:error, changeset} ->
          IO.puts("Failed to register user")
          IO.inspect(changeset.errors)
          raise "seeds failed: could not create user"
      end

    %User{} = user ->
      user
  end

IO.puts(
  "Seeded user #{user.email} (id=#{user.id}) for magic-link login (no password, may be unconfirmed)."
)
