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
    with_live_run(run_id, fn -> Beamwarden.RunServer.cancel(run_id) end)
  end

  def retry_task(run_id, task_id) do
    with_live_run(run_id, fn -> Beamwarden.RunServer.retry_task(run_id, task_id) end)
  end

  def logs(run_id) do
    with {:ok, snapshot} <- run_snapshot(run_id),
         {:ok, events} <- Beamwarden.EventStore.list(run_id) do
      {:ok, log_report(run_id, snapshot, events)}
    end
  end

  def cleanup_runs(opts \\ []) do
    opts
    |> Keyword.put_new_lazy(:older_than_seconds, fn -> Keyword.get(opts, :ttl_seconds, 3_600) end)
    |> Beamwarden.OrchestratorRetention.cleanup()
    |> then(&{:ok, &1})
  end

  def render_cleanup(report) do
    [
      "Cleanup Runs",
      "",
      "ttl_seconds=#{value(report, :ttl_seconds) || value(report, :older_than_seconds)}",
      "deleted_run_count=#{length(value(report, :deleted_run_ids) || value(report, :run_ids_removed) || [])}",
      "deleted_worker_count=#{length(value(report, :deleted_worker_ids) || value(report, :worker_ids_removed) || [])}",
      "deleted_event_count=#{length(value(report, :deleted_event_run_ids) || value(report, :event_run_ids_removed) || [])}",
      "skipped_active_count=#{length(value(report, :skipped_active_run_ids) || [])}",
      maybe_csv(
        "deleted_runs",
        value(report, :deleted_run_ids) || value(report, :run_ids_removed)
      ),
      maybe_csv(
        "deleted_workers",
        value(report, :deleted_worker_ids) || value(report, :worker_ids_removed)
      ),
      maybe_csv(
        "deleted_event_runs",
        value(report, :deleted_event_run_ids) || value(report, :event_run_ids_removed)
      ),
      maybe_csv("skipped_active_runs", value(report, :skipped_active_run_ids))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp maybe_csv(_label, nil), do: nil
  defp maybe_csv(_label, []), do: nil
  defp maybe_csv(label, values), do: "#{label}=#{Enum.join(values, ",")}"

  def follow_logs(run_id, sink, opts \\ []) when is_function(sink, 1) do
    with {:ok, snapshot} <- run_snapshot(run_id) do
      follow_via_broker_or_poll(run_id, snapshot, sink, opts)
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
    active_count = Enum.count(workers, &(value(&1, :health_state) == "active"))
    stale_count = Enum.count(workers, &(value(&1, :health_state) == "stale"))
    persisted_only_count = Enum.count(workers, &(value(&1, :presence) == "persisted"))

    [
      "Workers",
      "",
      "active_count=#{active_count}",
      "stale_count=#{stale_count}",
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
                "health_state=#{value(worker, :health_state) || "unknown"}",
                "current_task_id=#{value(worker, :current_task_id) || "none"}",
                "active_state=#{value(worker, :runtime_state) || "none"}",
                "persisted_state=#{value(worker, :persisted_state) || "none"}",
                "active_current_task_id=#{value(worker, :active_current_task_id) || "none"}",
                "persisted_current_task_id=#{value(worker, :persisted_current_task_id) || "none"}",
                maybe_text("health_reason", value(worker, :health_reason)),
                maybe_text("heartbeat_at", value(worker, :heartbeat_at)),
                maybe_text("heartbeat_timeout_at", value(worker, :heartbeat_timeout_at)),
                maybe_text("heartbeat_age_seconds", value(worker, :heartbeat_age_seconds)),
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
    events = value(report, :events) || []

    [
      "Run Logs",
      "",
      "run_id=#{value(report, :run_id)}",
      "run_status=#{value(report, :run_status)}",
      "run_lifecycle=#{value(report, :run_lifecycle)}",
      "event_source=#{value(report, :source) || "persisted"}",
      "follow_supported=#{value(report, :follow_supported)}",
      maybe_text("cursor", value(report, :cursor)),
      maybe_text("broker_node", value(report, :broker_node)),
      "event_count=#{length(events)}",
      if(events == [],
        do: "none",
        else:
          Enum.map(events, fn event ->
            format_event(event)
          end)
      )
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def render_event(event), do: format_event(event)

  defp with_live_run(run_id, fun) when is_function(fun, 0) do
    case run_snapshot(run_id) do
      {:ok, _snapshot} ->
        if Beamwarden.RunServer.running?(run_id), do: fun.(), else: {:error, :not_running}

      error ->
        error
    end
  end

  defp await_until(run_id, deadline) do
    case run_snapshot(run_id) do
      {:ok, snapshot} ->
        if terminal_status?(value(snapshot, :status)) or
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

  defp log_report(run_id, snapshot, events, opts \\ []) do
    active? = Beamwarden.RunServer.running?(run_id)

    %{
      run_id: run_id,
      run_status: value(snapshot, :status),
      run_lifecycle: value(snapshot, :lifecycle) || "active",
      source: Keyword.get(opts, :source, if(active?, do: "runtime", else: "persisted")),
      follow_supported: Keyword.get(opts, :follow_supported, active?),
      cursor: Keyword.get(opts, :cursor, last_event_seq(events)),
      broker_node: Keyword.get(opts, :broker_node),
      events: events
    }
  end

  defp follow_via_broker_or_poll(run_id, snapshot, sink, opts) do
    after_seq = Keyword.get(opts, :after_seq, 0)

    case attach_follow_stream(run_id, after_seq, opts) do
      {:ok, %{backlog: backlog, broker_node: broker_node, cursor: cursor}} ->
        sink.(
          render_logs(
            log_report(run_id, snapshot, backlog,
              source: "replay",
              follow_supported: true,
              cursor: cursor,
              broker_node: broker_node
            )
          )
        )

        sink.("follow=history seq=#{cursor}")

        cond do
          terminal_status?(value(snapshot, :status)) ->
            Beamwarden.LogBroker.unsubscribe(run_id)
            sink.("follow=complete status=#{value(snapshot, :status)} seq=#{cursor}")
            :ok

          true ->
            sink.("follow=live broker_node=#{broker_node} seq=#{cursor}")
            do_follow_broker_logs(run_id, cursor, sink, snapshot, opts)
        end

      {:error, reason} ->
        {:ok, backlog} = Beamwarden.EventStore.list_since(run_id, after_seq)
        cursor = max(after_seq, last_event_seq(backlog))

        sink.(
          render_logs(
            log_report(run_id, snapshot, mark_event_source(backlog, "replay"),
              source: "degraded-persisted",
              follow_supported: true,
              cursor: cursor
            )
          )
        )

        sink.("follow=history seq=#{cursor}")

        cond do
          terminal_status?(value(snapshot, :status)) ->
            sink.("follow=complete status=#{value(snapshot, :status)} seq=#{cursor}")
            :ok

          true ->
            sink.("follow=degraded-persisted reason=#{format_reason(reason)}")
            do_follow_persisted_logs(run_id, cursor, sink, snapshot, opts)
        end
    end
  end

  defp do_follow_broker_logs(run_id, cursor, sink, snapshot, opts) do
    interval_ms = Keyword.get(opts, :interval_ms, 50)
    timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)

    started_at =
      Keyword.get_lazy(opts, :started_at, fn -> System.monotonic_time(:millisecond) end)

    receive do
      {:beamwarden_log_broker, ^run_id, event} ->
        next_cursor = max(cursor, event_seq(event) || cursor)
        sink.(render_event(event))

        {:ok, latest_snapshot} = run_snapshot(run_id)

        do_follow_broker_logs(run_id, next_cursor, sink, latest_snapshot,
          interval_ms: interval_ms,
          timeout_ms: timeout_ms,
          started_at: started_at
        )
    after
      interval_ms ->
        cond do
          terminal_status?(value(snapshot, :status)) ->
            Beamwarden.LogBroker.unsubscribe(run_id)
            sink.("follow=complete status=#{value(snapshot, :status)} seq=#{cursor}")
            :ok

          System.monotonic_time(:millisecond) - started_at >= timeout_ms ->
            Beamwarden.LogBroker.unsubscribe(run_id)
            sink.("follow=timeout status=#{value(snapshot, :status)} seq=#{cursor}")
            :ok

          true ->
            {:ok, latest_snapshot} = run_snapshot(run_id)

            do_follow_broker_logs(run_id, cursor, sink, latest_snapshot,
              interval_ms: interval_ms,
              timeout_ms: timeout_ms,
              started_at: started_at
            )
        end
    end
  end

  defp do_follow_persisted_logs(run_id, cursor, sink, snapshot, opts) do
    interval_ms = Keyword.get(opts, :interval_ms, 50)
    timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)

    started_at =
      Keyword.get_lazy(opts, :started_at, fn -> System.monotonic_time(:millisecond) end)

    cond do
      terminal_status?(value(snapshot, :status)) ->
        sink.("follow=complete status=#{value(snapshot, :status)} seq=#{cursor}")
        :ok

      System.monotonic_time(:millisecond) - started_at >= timeout_ms ->
        sink.("follow=timeout status=#{value(snapshot, :status)} seq=#{cursor}")
        :ok

      true ->
        Process.sleep(interval_ms)
        {:ok, events} = Beamwarden.EventStore.list_since(run_id, cursor)

        next_cursor =
          events
          |> mark_event_source("degraded-persisted")
          |> Enum.reduce(cursor, fn event, acc ->
            sink.(render_event(event))
            max(acc, event_seq(event) || acc)
          end)

        {:ok, latest_snapshot} = run_snapshot(run_id)

        do_follow_persisted_logs(run_id, next_cursor, sink, latest_snapshot,
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

  defp terminal_status?(status), do: status in ["completed", "failed", "cancelled"]

  defp attach_follow_stream(run_id, after_seq, opts) do
    case if(Keyword.get(opts, :broker, true) == false, do: {:error, :broker_disabled}, else: :ok) do
      :ok -> Beamwarden.LogBroker.subscribe(run_id, after_seq)
      error -> error
    end
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: to_string(reason)

  defp mark_event_source(events, source) do
    Enum.map(events, &Map.put(&1, "source", source))
  end

  defp last_event_seq([]), do: 0
  defp last_event_seq(events), do: events |> List.last() |> event_seq() || 0

  defp format_event(event) do
    [
      "[#{value(event, :timestamp)}]",
      value(event, :type),
      maybe_text("event_seq", event_seq(event)),
      maybe_text("seq", event_seq(event)),
      maybe_text("source", value(event, :source)),
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

  defp value(nil, _key), do: nil

  defp value(map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> nil
    end
  end

  defp event_seq(nil), do: nil
  defp event_seq(event), do: value(event, :event_seq) || value(event, :seq)
end
