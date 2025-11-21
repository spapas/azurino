defmodule Azurino.AzureFilenameTest do
  use ExUnit.Case, async: true

  alias Azurino.Azure

  test "preserves filename when no collision" do
    exists_fun = fn _sas, _path -> false end

    filename = "sync-time.bat"
    result = Azure.make_unique_filename(nil, "", filename, exists_fun)

    assert result == filename
  end

  test "adds random string before extension when collision" do
    exists_fun = fn _sas, _path -> true end

    filename = "sync-time.bat"
    result = Azure.make_unique_filename(nil, "", filename, exists_fun)

    # Expect pattern: base . <10 chars> .ext
    assert Regex.match?(~r/^sync-time\.[A-Za-z0-9_-]{10}\.bat$/, result)
  end

  test "retries until available when initial candidates collide" do
    # Agent keeps a call count so we can simulate collisions for the first two checks
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    attempts_to_fail = 2

    exists_fun = fn _sas, _path ->
      n = Agent.get_and_update(agent, fn c -> {c + 1, c + 1} end)
      n <= attempts_to_fail
    end

    filename = "sync-time.bat"
    result = Azure.make_unique_filename(nil, "", filename, exists_fun)

    # After two collisions we expect a randomized candidate to be returned
    assert Regex.match?(~r/^sync-time\.[A-Za-z0-9_-]{10}\.bat$/, result)

    # Ensure the exists_fun was called at least three times (original + two collisions)
    final_calls = Agent.get(agent, & &1)
    assert final_calls >= 3
  end

  test "falls back to timestamp when all attempts collide" do
    exists_fun = fn _sas, _path -> true end

    filename = "sync-time.bat"
    # Limit attempts to 3 for the test to exercise fallback quickly
    result = Azure.make_unique_filename(nil, "", filename, exists_fun, 3)

    # Expect a timestamp-based fallback: base . digits . ext
    assert Regex.match?(~r/^sync-time\.\d+\.bat$/, result)
  end
end
