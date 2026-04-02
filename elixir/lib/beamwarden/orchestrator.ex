defmodule Beamwarden.Orchestrator do
  @moduledoc false

  def start_run(prompt, opts \\ []) do
    run_id =
      Keyword.get_lazy(opts, :run_id, fn ->
        "run-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
      end)

    start_opts =
      opts
      |> Keyword.put(:run_id, run_id)
      |> Keyword.put(:prompt, prompt)

    case DynamicSupervisor.start_child(
           Beamwarden.RunSupervisor,
           {Beamwarden.RunServer, start_opts}
         ) do
      {:ok, _pid} ->
        await_run(run_id, Keyword.get(opts, :await_timeout, 1_000))

      {:error, {:already_started, _pid}} ->
        run_snapshot(run_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def await_run(run_id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_until(run_id, deadline)
  end

  def run_snapshot(run_id) do
    cond do
      Beamwarden.RunServer.running?(run_id) ->
        {:ok, Beamwarden.RunServer.snapshot(run_id)}

      true ->
        case Beamwarden.RunStore.load(run_id) do
          {:ok, snapshot} -> {:ok, normalize_persisted_snapshot(snapshot)}
          error -> error
        end
    end
  end

  def task_list(run_id) do
    with {:ok, snapshot} <- run_snapshot(run_id) do
      {:ok, value(snapshot, :tasks) || []}
    end
  end

  def cancel_run(run_id) do
    case run_snapshot(run_id) do
      {:ok, _snapshot} ->
        if Beamwarden.RunServer.running?(run_id) do
          Beamwarden.RunServer.cancel(run_id)
        else
          {:error, :not_running}
        end

      error ->
        error
    end
  end

  def retry_task(run_id, task_id) do
    case run_snapshot(run_id) do
      {:ok, _snapshot} ->
        if Beamwarden.RunServer.running?(run_id) do
          Beamwarden.RunServer.retry_task(run_id, task_id)
        else
          {:error, :not_running}
        end

      error ->
        error
    end
  end

  def logs(run_id) do
    with {:ok, snapshot} <- run_snapshot(run_id),
         {:ok, events} <- Beamwarden.EventStore.list(run_id) do
      active? = Beamwarden.RunServer.running?(run_id)

      {:ok,
       %{
         run_id: run_id,
         run_status: value(snapshot, :status),
         run_lifecycle: value(snapshot, :lifecycle) || "active",
         source: if(active?, do: "runtime", else: "persisted"),
         follow_supported: active?,
         events: events
       }}
    end
  end

  def cleanup_runs(opts \\ []) do
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 3_600)
    cutoff = DateTime.add(DateTime.utc_now(), -ttl_seconds, :second)

    runs = Beamwarden.RunStore.list()

    {stale_runs, skipped_active_runs} =
      Enum.split_with(runs, fn run ->
        run_id = value(run, :run_id)

        !Beamwarden.RunServer.running?(run_id) and
          cleanup_eligible_run?(run) and
          older_than?(value(run, :updated_at), cutoff)
      end)

    deleted_run_ids =
      stale_runs
      |> Enum.map(&value(&1, :run_id))
      |> Enum.each(&Beamwarden.RunStore.delete/1)
      |> then(fn _ -> Enum.map(stale_runs, &value(&1, :run_id)) end)

    deleted_run_id_set = MapSet.new(deleted_run_ids)

    deleted_worker_ids =
      Beamwarden.WorkerStore.list()
      |> Enum.filter(fn worker ->
        worker_id = value(worker, :worker_id)
        run_id = value(worker, :run_id)

        Beamwarden.WorkerSupervisor.worker_pid(worker_id) == :error and
          (MapSet.member?(deleted_run_id_set, run_id) or
             ((is_nil(run_id) or !Beamwarden.RunServer.running?(run_id)) and
                older_than?(worker_freshness_timestamp(worker), cutoff)))
      end)
      |> Enum.map(fn worker ->
        worker_id = value(worker, :worker_id)
        :ok = Beamwarden.WorkerStore.delete(worker_id)
        worker_id
      end)

    deleted_event_run_ids =
      Beamwarden.EventStore.list_run_ids()
      |> Enum.filter(fn run_id ->
        MapSet.member?(deleted_run_id_set, run_id) or
          (!Beamwarden.RunServer.running?(run_id) and not run_exists?(run_id) and
             older_than?(event_timestamp(run_id), cutoff))
      end)
      |> Enum.map(fn run_id ->
        :ok = Beamwarden.EventStore.delete(run_id)
        run_id
      end)

    {:ok,
     %{
       ttl_seconds: ttl_seconds,
       deleted_run_ids: deleted_run_ids,
       deleted_worker_ids: deleted_worker_ids,
       deleted_event_run_ids: deleted_event_run_ids,
       skipped_active_run_ids: Enum.map(skipped_active_runs, &value(&1, :run_id))
     }}
  end

  def render_cleanup(report) do
    [
      "Cleanup Runs",
      "",
      "ttl_seconds=#{value(report, :ttl_seconds)}",
      "deleted_run_count=#{length(value(report, :deleted_run_ids) || [])}",
      "deleted_worker_count=#{length(value(report, :deleted_worker_ids) || [])}",
      "deleted_event_count=#{length(value(report, :deleted_event_run_ids) || [])}",
      "skipped_active_count=#{length(value(report, :skipped_active_run_ids) || [])}",
      maybe_csv("deleted_runs", value(report, :deleted_run_ids)),
      maybe_csv("deleted_workers", value(report, :deleted_worker_ids)),
      maybe_csv("deleted_event_runs", value(report, :deleted_event_run_ids)),
      maybe_csv("skipped_active_runs", value(report, :skipped_active_run_ids))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp maybe_csv(_label, nil), do: nil
  defp maybe_csv(_label, []), do: nil
  defp maybe_csv(label, values), do: "#{label}=#{Enum.join(values, ",")}"

  defp cleanup_eligible_run?(run) do
    value(run, :status) in ["completed", "failed", "cancelled"]
  end

  defp worker_freshness_timestamp(worker) do
    value(worker, :last_event_at) ||
      value(worker, :heartbeat_at) ||
      value(worker, :updated_at) ||
      value(worker, :started_at)
  end

  defp event_timestamp(run_id) do
    path = Beamwarden.event_path(run_id)

    with {:ok, stat} <- File.stat(path),
         {:ok, datetime} <- DateTime.from_unix(stat.mtime) do
      datetime
    else
      _ -> nil
    end
  end

  def follow_logs(run_id, sink, opts \\ []) when is_function(sink, 1) do
    with {:ok, snapshot} <- run_snapshot(run_id),
         {:ok, events} <- Beamwarden.EventStore.list(run_id) do
      sink.(render_logs(run_id, events))
      sink.("follow=streaming")
      do_follow_logs(run_id, length(events), sink, snapshot, opts)
    end
  end

  def worker_list(opts \\ []) do
    Beamwarden.WorkerSupervisor.list_workers(opts)
  end

  def cleanup_state(opts \\ []) do
    Beamwarden.OrchestratorRetention.cleanup(opts)
  end

  def render_run(snapshot) do
    [
      "Run Snapshot",
      "",
      "run_id=#{value(snapshot, :run_id)}",
      "presence=#{value(snapshot, :presence) || "unknown"}",
      "status=#{value(snapshot, :status)}",
      "lifecycle=#{value(snapshot, :lifecycle) || "active"}",
      "task_count=#{value(snapshot, :task_count)}",
      "completed_count=#{value(snapshot, :completed_count)}",
      "failed_count=#{value(snapshot, :failed_count)}",
      "cancelling_count=#{value(snapshot, :cancelling_count) || 0}",
      "cancelled_count=#{value(snapshot, :cancelled_count) || 0}",
      "worker_count=#{length(value(snapshot, :worker_ids) || [])}",
      maybe_text("lifecycle", value(snapshot, :lifecycle)),
      maybe_text("stale_runtime", if(truthy?(snapshot, :stale_runtime), do: "true")),
      maybe_text("stale_reason", value(snapshot, :stale_reason)),
      "updated_at=#{value(snapshot, :updated_at)}",
      maybe_text("finished_at", value(snapshot, :finished_at)),
      maybe_text("cancellation_requested_at", value(snapshot, :cancellation_requested_at)),
      "prompt=#{value(snapshot, :prompt)}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def render_tasks(run_id, tasks) do
    [
      "Run Tasks",
      "",
      "run_id=#{run_id}",
      Enum.map(tasks, fn task ->
        [
          "[#{value(task, :status)}] #{value(task, :task_id)}",
          "attempt=#{value(task, :attempt) || 1}",
          "worker=#{value(task, :assigned_worker) || "none"}",
          maybe_text("summary", value(task, :result_summary)),
          maybe_text("error", value(task, :error))
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
      end)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def render_workers(workers) do
    active_count = Enum.count(workers, &truthy?(&1, :active))
    persisted_only_count = Enum.count(workers, &(value(&1, :presence) == "persisted"))

    [
      "Workers",
      "",
      "active_count=#{active_count}",
      "persisted_only_count=#{persisted_only_count}",
      if(workers == [],
        do: "none",
        else:
          Enum.map(workers, fn worker ->
            Enum.join(
              [
                "worker_id=#{value(worker, :worker_id)}",
                "run_id=#{value(worker, :run_id)}",
                "presence=#{value(worker, :presence) || "unknown"}",
                "state=#{value(worker, :state)}",
                "current_task_id=#{value(worker, :current_task_id) || "none"}",
                "active_state=#{value(worker, :runtime_state) || "none"}",
                "persisted_state=#{value(worker, :persisted_state) || "none"}",
                "active_current_task_id=#{value(worker, :active_current_task_id) || "none"}",
                "persisted_current_task_id=#{value(worker, :persisted_current_task_id) || "none"}",
                maybe_text("last_task_status", value(worker, :last_task_status)),
                maybe_text("persisted_state", persisted_state_text(worker)),
                maybe_text("last_result", value(worker, :last_result_summary))
              ],
              " "
            )
          end)
      )
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def render_logs(report) do
    [
      "Run Logs",
      "",
      "run_id=#{run_id}",
      "source=persisted_events",
      "event_count=#{length(events)}",
      if(events == [],
        do: "none",
        else:
          Enum.map(value(report, :events) || [], fn event ->
            format_event(event)
          end)
      )
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def render_cleanup(summary) do
    [
      "Cleanup Summary",
      "",
      "older_than_seconds=#{value(summary, :older_than_seconds)}",
      "runs_deleted=#{value(summary, :runs_deleted) || 0}",
      "workers_deleted=#{value(summary, :workers_deleted) || 0}",
      "events_deleted=#{value(summary, :events_deleted) || 0}",
      "run_ids_removed=#{Enum.join(value(summary, :run_ids_removed) || [], ",")}",
      "worker_ids_removed=#{Enum.join(value(summary, :worker_ids_removed) || [], ",")}",
      "event_run_ids_removed=#{Enum.join(value(summary, :event_run_ids_removed) || [], ",")}"
    ]
    |> Enum.join("\n")
  end

  def render_event(event), do: format_event(event)

  defp await_until(run_id, deadline) do
    case run_snapshot(run_id) do
      {:ok, snapshot} ->
        if value(snapshot, :status) in ["completed", "failed", "cancelled"] or
             System.monotonic_time(:millisecond) >= deadline do
          {:ok, snapshot}
        else
          Process.sleep(25)
          await_until(run_id, deadline)
        end

      error ->
        error
    end
  end

  defp maybe_text(_label, nil), do: nil
  defp maybe_text(_label, ""), do: nil
  defp maybe_text(label, value), do: "#{label}=#{value}"
  defp truthy?(map, key), do: value(map, key) in [true, "true"]

  defp do_follow_logs(run_id, seen_count, sink, snapshot, opts) do
    interval_ms = Keyword.get(opts, :interval_ms, 50)
    timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)
    started_at = Keyword.get_lazy(opts, :started_at, fn -> System.monotonic_time(:millisecond) end)

    cond do
      value(snapshot, :status) in ["completed", "failed", "cancelled"] ->
        sink.("follow=complete status=#{value(snapshot, :status)}")
        :ok

      System.monotonic_time(:millisecond) - started_at >= timeout_ms ->
        sink.("follow=timeout status=#{value(snapshot, :status)}")
        :ok

      true ->
        Process.sleep(interval_ms)
        {:ok, events} = Beamwarden.EventStore.list(run_id)

        events
        |> Enum.drop(seen_count)
        |> Enum.each(&(sink.(render_event(&1))))

        {:ok, latest_snapshot} = run_snapshot(run_id)

        do_follow_logs(run_id, length(events), sink, latest_snapshot,
          interval_ms: interval_ms,
          timeout_ms: timeout_ms,
          started_at: started_at
        )
    end
  end

  defp normalize_persisted_snapshot(snapshot) do
    snapshot
    |> Map.put_new("presence", "persisted")
    |> maybe_mark_stale_runtime()
  end

  defp maybe_mark_stale_runtime(snapshot) do
    if value(snapshot, :status) in ["pending", "running", "cancelling"] do
      snapshot
      |> Map.put("stale_runtime", true)
      |> Map.put_new("stale_reason", "run_server_not_registered")
    else
      snapshot
    end
  end

  defp persisted_state_text(worker) do
    persisted_state = value(worker, :persisted_state)
    runtime_state = value(worker, :runtime_state)

    if persisted_state && persisted_state != runtime_state, do: persisted_state
  end

  defp format_event(event) do
    [
      "[#{value(event, :timestamp)}]",
      value(event, :type),
      maybe_text("task_id", value(event, :task_id)),
      maybe_text("worker_id", value(event, :worker_id)),
      maybe_text("attempt", value(event, :attempt)),
      maybe_text("summary", value(event, :summary)),
      maybe_text("error", value(event, :error)),
      maybe_text("reason", value(event, :reason)),
      maybe_text("prompt", value(event, :prompt)),
      maybe_text("title", value(event, :title)),
      maybe_text("completed_count", value(event, :completed_count)),
      maybe_text("failed_count", value(event, :failed_count)),
      maybe_text("cancelled_count", value(event, :cancelled_count))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
