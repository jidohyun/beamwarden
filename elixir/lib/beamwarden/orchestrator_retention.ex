defmodule Beamwarden.OrchestratorRetention do
  @moduledoc false

  def cleanup(opts \\ []) do
    older_than_seconds = Keyword.get(opts, :older_than_seconds, default_retention_seconds())
    cutoff = DateTime.add(DateTime.utc_now(), -older_than_seconds, :second)

    run_ids_removed =
      Beamwarden.RunStore.list()
      |> Enum.filter(&expired_terminal_run?(&1, cutoff))
      |> Enum.map(fn snapshot ->
        run_id = value(snapshot, :run_id)
        :ok = Beamwarden.RunStore.delete(run_id)
        run_id
      end)

    worker_ids_removed =
      Beamwarden.WorkerStore.list()
      |> Enum.filter(&expired_worker?(&1, cutoff))
      |> Enum.map(fn snapshot ->
        worker_id = value(snapshot, :worker_id)
        :ok = Beamwarden.WorkerStore.delete(worker_id)
        worker_id
      end)

    event_run_ids_removed =
      (run_ids_removed ++ stale_event_run_ids(cutoff))
      |> Enum.uniq()
      |> Enum.filter(fn run_id ->
        if Beamwarden.RunServer.running?(run_id) do
          false
        else
          :ok = Beamwarden.EventStore.delete(run_id)
          true
        end
      end)

    %{
      older_than_seconds: older_than_seconds,
      run_ids_removed: run_ids_removed,
      worker_ids_removed: worker_ids_removed,
      event_run_ids_removed: event_run_ids_removed,
      runs_deleted: length(run_ids_removed),
      workers_deleted: length(worker_ids_removed),
      events_deleted: length(event_run_ids_removed)
    }
  end

  defp expired_terminal_run?(snapshot, cutoff) do
    run_id = value(snapshot, :run_id)
    status = value(snapshot, :status)

    status in ["completed", "failed", "cancelled"] and
      not Beamwarden.RunServer.running?(run_id) and
      older_than_cutoff?(snapshot_time(snapshot, [:finished_at, :updated_at, :created_at]), cutoff)
  end

  defp expired_worker?(snapshot, cutoff) do
    worker_id = value(snapshot, :worker_id)

    Beamwarden.WorkerSupervisor.worker_pid(worker_id) == :error and
      older_than_cutoff?(
        snapshot_time(snapshot, [:last_event_at, :heartbeat_at, :started_at]),
        cutoff
      )
  end

  defp stale_event_run_ids(cutoff) do
    Beamwarden.EventStore.run_ids()
    |> Enum.filter(fn run_id ->
      not Beamwarden.RunServer.running?(run_id) and
        event_file_older_than_cutoff?(run_id, cutoff) and
        match?({:error, :not_found}, Beamwarden.RunStore.load(run_id))
    end)
  end

  defp event_file_older_than_cutoff?(run_id, cutoff) do
    case File.stat(Beamwarden.event_path(run_id), time: :posix) do
      {:ok, stat} ->
        stat.mtime
        |> DateTime.from_unix!()
        |> DateTime.compare(cutoff) in [:lt, :eq]

      {:error, _reason} ->
        false
    end
  end

  defp older_than_cutoff?(nil, _cutoff), do: false

  defp older_than_cutoff?(%DateTime{} = datetime, cutoff) do
    DateTime.compare(datetime, cutoff) in [:lt, :eq]
  end

  defp snapshot_time(snapshot, keys) do
    Enum.find_value(keys, fn key ->
      case value(snapshot, key) do
        nil -> nil
        value -> parse_datetime(value)
      end
    end)
  end

  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp default_retention_seconds do
    case System.get_env("BEAMWARDEN_ORCHESTRATOR_RETENTION_SECONDS") do
      nil -> 86_400
      value -> String.to_integer(value)
    end
  rescue
    _ -> 86_400
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
