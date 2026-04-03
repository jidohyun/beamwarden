defmodule Beamwarden.EventStore do
  @moduledoc false

  def append(run_id, event) do
    File.mkdir_p!(Beamwarden.event_root())
    event_seq = next_seq(run_id)

    entry =
      event
      |> Map.new()
      |> Map.put_new(:run_id, run_id)
      |> Map.put_new(:timestamp, now())
      |> Map.put_new(:persisted_at, now())
      |> Map.put_new(:seq, event_seq)
      |> Map.put_new(:event_seq, event_seq)

    Beamwarden.event_path(run_id)
    |> File.write!(JSON.encode!(entry) <> "\n", [:append])

    entry
  end

  def list(run_id) do
    {:ok, read_entries(run_id)}
  end

  def list_since(run_id, seq) when is_integer(seq) and seq >= 0 do
    {:ok, Enum.filter(read_entries(run_id), &(value(&1, :seq) > seq))}
  end

  def delete(run_id) do
    Beamwarden.event_path(run_id)
    |> File.rm()
    |> case do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  def run_ids do
    Beamwarden.event_root()
    |> Path.join("*.jsonl")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".jsonl"))
    |> Enum.sort()
  end

  def last_seq(run_id) do
    read_entries(run_id)
    |> List.last()
    |> event_seq()
    |> Kernel.||(0)
  end

  defp next_seq(run_id), do: last_seq(run_id) + 1

  defp read_entries(run_id) do
    case File.read(Beamwarden.event_path(run_id)) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.map(&JSON.decode!/1)
        |> Enum.with_index(1)
        |> Enum.map(fn {entry, index} ->
          event_seq = event_seq(entry) || index

          entry
          |> Map.put_new("run_id", run_id)
          |> Map.put_new("timestamp", now())
          |> Map.put_new("persisted_at", value(entry, :timestamp) || now())
          |> Map.put_new("seq", event_seq)
          |> Map.put_new("event_seq", event_seq)
        end)

      {:error, :enoent} ->
        []
    end
  end

  defp value(nil, _key), do: nil
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp event_seq(nil), do: nil
  defp event_seq(entry), do: value(entry, :event_seq) || value(entry, :seq)

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
