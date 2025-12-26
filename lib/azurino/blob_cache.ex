defmodule Azurino.BlobCache do
  require Logger
  use GenServer

  @ttl :timer.minutes(5)

  # Client API -------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def list_container(bucket_name \\ "default") do
    GenServer.call(__MODULE__, {:list_container, bucket_name})
  end

  # Server callbacks -------------------

  @impl true
  def init(_) do
    {:ok, %{}
    }
  end

  @impl true
  def handle_call({:list_container, bucket_name}, _from, state) do
    now = System.system_time(:millisecond)

    entry = Map.get(state, bucket_name)

    case entry do
      %{data: data, timestamp: ts} when not is_nil(ts) and now - ts < @ttl ->
        Logger.info("Serving from cache")
        {:reply, {:ok, data}, state}

      _ ->
        result = Azurino.Azure.list_container_no_cache(bucket_name)
        Logger.info("Fetching fresh data")

        new_state =
          case result do
            {:ok, data} ->
              Map.put(state, bucket_name, %{data: data, timestamp: now})

            {:error, _} ->
              state
          end

        {:reply, result, new_state}
    end
  end
end
