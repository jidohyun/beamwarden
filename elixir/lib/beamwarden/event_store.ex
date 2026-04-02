defmodule Beamwarden.EventStore do
  @moduledoc false

  def append(run_id, event) do
    File.mkdir_p!(Beamwarden.event_root())

    entry =
      event
      |> Map.new()
      |> Map.put_new(:run_id, run_id)
      |> Map.put_new(:timestamp, now())

    Beamwarden.event_path(run_id)
    |> File.write!(JSON.encode!(entry) <> "\n", [:append])

    entry
  end

  def list(run_id) do
    case File.read(Beamwarden.event_path(run_id)) do
      {:ok, contents} ->
        {:ok,
         contents
         |> String.split("\n", trim: true)
         |> Enum.map(&JSON.decode!/1)}

      {:error, :enoent} ->
        {:ok, []}
    end
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
