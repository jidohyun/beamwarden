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
    [
      "Workers",
      "",
      if(workers == [],
        do: "none",
        else:
          Enum.map(workers, fn worker ->
            Enum.join(
              [
                "worker_id=#{value(worker, :worker_id)}",
                "run_id=#{value(worker, :run_id)}",
                "state=#{value(worker, :state)}",
                "current_task_id=#{value(worker, :current_task_id) || "none"}"
              ],
              " "
            )
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
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
