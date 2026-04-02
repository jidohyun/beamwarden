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
        Beamwarden.RunStore.load(run_id)
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
    with {:ok, _snapshot} <- run_snapshot(run_id),
         {:ok, events} <- Beamwarden.EventStore.list(run_id) do
      {:ok, events}
    end
  end

  def worker_list(opts \\ []) do
    Beamwarden.WorkerSupervisor.list_workers(opts)
  end

  def render_run(snapshot) do
    [
      "Run Snapshot",
      "",
      "run_id=#{value(snapshot, :run_id)}",
      "status=#{value(snapshot, :status)}",
      "task_count=#{value(snapshot, :task_count)}",
      "completed_count=#{value(snapshot, :completed_count)}",
      "failed_count=#{value(snapshot, :failed_count)}",
      "cancelled_count=#{value(snapshot, :cancelled_count) || 0}",
      "worker_count=#{length(value(snapshot, :worker_ids) || [])}",
      "updated_at=#{value(snapshot, :updated_at)}",
      "prompt=#{value(snapshot, :prompt)}"
    ]
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

  def render_logs(run_id, events) do
    [
      "Run Logs",
      "",
      "run_id=#{run_id}",
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

  defp await_until(run_id, deadline) do
    case run_snapshot(run_id) do
      {:ok, snapshot} ->
        if value(snapshot, :status) in ["completed", "failed"] or
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
