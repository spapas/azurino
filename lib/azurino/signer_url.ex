defmodule Azurino.SignedURL do
  import Bitwise

  @default_expires_in 300

  defp get_secret_key do
    Application.get_env(:azurino, :secret_key)
  end

  def secret_key, do: get_secret_key()

  @moduledoc """
  Module για δημιουργία και επαλήθευση signed URLs για secure file sharing.

  ## Παραδείγματα

      # Δημιουργία signed URL
      signed_url = SignedURL.sign(
        secret_key: "my-secret-key",
        path: "/files/document.pdf",
        expires_in: 3600  # 1 ώρα
      )

      # Επαλήθευση signed URL
      case SignedURL.verify("https://example.com/files/document.pdf?signature=...&expires=...", "my-secret-key") do
        {:ok, path} -> {:ok, path}
        {:error, :expired} -> {:error, "Το link έχει λήξει"}
        {:error, :invalid} -> {:error, "Μη έγκυρη υπογραφή"}
      end
  """

  @doc """
  Δημιουργεί ένα signed URL για ένα αρχείο.

  ## Παράμετροι

    * `:secret_key` - Το μυστικό κλειδί για υπογραφή (required)
    * `:path` - Το path του αρχείου (required)
    * `:expires_in` - Χρόνος λήξης σε δευτερόλεπτα (optional, default: 3600)
    * `:metadata` - Extra metadata για υπογραφή (optional, default: %{})

  ## Επιστρέφει

  String με το πλήρες signed URL.
  """
  def sign(opts, secret_key \\ nil) do
    secret_key = secret_key || get_secret_key()
    path = Keyword.fetch!(opts, :path)
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)
    metadata = Keyword.get(opts, :metadata, %{})

    # Υπολογισμός timestamp λήξης
    expires_at = System.system_time(:second) + expires_in

    # Δημιουργία υπογραφής
    signature = generate_signature(secret_key, path, expires_at, metadata)

    %{
      "signature" => signature,
      "expires" => Integer.to_string(expires_at),
      "path" => path
    }
    |> Map.merge(metadata)

    # |> URI.encode_query()
  end

  @doc """
  Επαληθεύει ένα signed URL.

  ## Παράμετροι

    * `url` - Το signed URL προς επαλήθευση
    * `secret_key` - Το μυστικό κλειδί
    * `opts` - Επιπλέον επιλογές:
      * `:extract_metadata` - Αν true, επιστρέφει και τα metadata (default: false)

  ## Επιστρέφει

    * `{:ok, path}` - Αν η υπογραφή είναι έγκυρη
    * `{:ok, {path, metadata}}` - Αν extract_metadata: true
    * `{:error, :expired}` - Αν το URL έχει λήξει
    * `{:error, :invalid}` - Αν η υπογραφή δεν είναι έγκυρη
    * `{:error, :missing_params}` - Αν λείπουν απαραίτητες παράμετροι
  """
  def verify(params, secret_key \\ nil, opts \\ []) do
    secret_key = secret_key || get_secret_key()
    extract_metadata = Keyword.get(opts, :extract_metadata, false)

    with {:ok, signature} <- Map.fetch(params, "signature"),
         {:ok, expires_str} <- Map.fetch(params, "expires"),
         {:ok, path} <- Map.fetch(params, "path"),
         {expires_at, ""} <- Integer.parse(expires_str) do
      # Έλεγχος λήξης
      current_time = System.system_time(:second)

      if current_time > expires_at do
        {:error, :expired}
      else
        # Αφαίρεση signature από params για να πάρουμε τα metadata
        metadata = Map.drop(params, ["signature", "expires", "path"])

        # Υπολογισμός αναμενόμενης υπογραφής
        expected_signature = generate_signature(secret_key, path, expires_at, metadata)

        # Σύγκριση υπογραφών (constant-time)
        if secure_compare(signature, expected_signature) do
          if extract_metadata and map_size(metadata) > 0 do
            {:ok, {path, metadata}}
          else
            {:ok, path}
          end
        else
          {:error, :invalid}
        end
      end
    else
      :error -> {:error, :missing_params}
    end
  end

  @doc """
  Ελέγχει αν ένα signed URL είναι έγκυρο (χωρίς να επιστρέψει το path).
  """
  def valid?(url, secret_key) do
    case verify(url, secret_key) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Επιστρέφει τον υπολειπόμενο χρόνο ζωής ενός signed URL σε δευτερόλεπτα.

  ## Επιστρέφει

    * `{:ok, seconds}` - Δευτερόλεπτα μέχρι τη λήξη (0 αν έχει λήξει)
    * `{:error, reason}` - Αν υπάρχει πρόβλημα με το URL
  """
  def time_remaining(url) do
    uri = URI.parse(url)

    params =
      case uri.query do
        nil -> %{}
        query -> URI.decode_query(query)
      end

    with {:ok, expires_str} <- Map.fetch(params, "expires"),
         {expires_at, ""} <- Integer.parse(expires_str) do
      current_time = System.system_time(:second)
      remaining = max(0, expires_at - current_time)
      {:ok, remaining}
    else
      :error -> {:error, :missing_expires}
      _ -> {:error, :invalid_expires}
    end
  end

  # Private functions

  defp generate_signature(secret_key, path, expires_at, metadata) do
    # Δημιουργία string προς υπογραφή
    metadata_string =
      metadata
      |> Enum.sort()
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("&")

    data = "#{path}|#{expires_at}|#{metadata_string}"

    # HMAC-SHA256 signature
    :crypto.mac(:hmac, :sha256, secret_key, data)
    |> Base.url_encode64(padding: false)
  end

  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    a_bytes = :binary.bin_to_list(a)
    b_bytes = :binary.bin_to_list(b)

    Enum.zip(a_bytes, b_bytes)
    |> Enum.reduce(0, fn {x, y}, acc -> acc ||| Bitwise.bxor(x, y) end)
    |> Kernel.==(0)
  end
end
