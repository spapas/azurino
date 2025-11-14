defmodule Azurino.BlobCache do
  require Logger
  use GenServer

  @ttl :timer.minutes(5)

  # Client API -------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def list_container do
    GenServer.call(__MODULE__, :list_container)
  end

  # Server callbacks -------------------

  @impl true
  def init(_) do
    {:ok, %{data: nil, timestamp: nil}}
  end

  @impl true
  def handle_call(:list_container, _from, state) do
    now = System.system_time(:millisecond)

    case state do
      %{data: data, timestamp: ts} when not is_nil(ts) and now - ts < @ttl ->
        Logger.info("Serving from cache")
        {:reply, {:ok, data}, state}

      _ ->
        # Fetch fresh data
        result = Azurino.Azure.list_container_no_cache()
        Logger.info("Fetching fresh data")

        new_state =
          case result do
            {:ok, data} ->
              %{data: data, timestamp: now}

            {:error, _} ->
              # Don't update cache on error
              state
          end

        {:reply, result, new_state}
    end
  end
end
