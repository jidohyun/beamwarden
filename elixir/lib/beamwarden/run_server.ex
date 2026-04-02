defmodule Beamwarden.RunServer do
  @moduledoc false

  use GenServer

  alias Beamwarden.{ExternalWorker, TaskScheduler}

  defstruct [
    :run_id,
    :prompt,
    :created_at,
    :updated_at,
    :worker_count,
    status: "pending",
    tasks: [],
    workers: %{}
  ]

  def child_spec(opts) do
    run_id = Keyword.fetch!(opts, :run_id)

    %{
      id: {__MODULE__, run_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  def start_run(prompt, opts \\ []) when is_binary(prompt) do
    run_id = Keyword.get(opts, :run_id) || generate_run_id()
    worker_count = Keyword.get(opts, :workers, 1)

    with {:ok, _pid} <-
           DynamicSupervisor.start_child(
             Beamwarden.RunSupervisor,
             {__MODULE__, run_id: run_id, prompt: prompt, workers: worker_count}
           ),
         :ok <- bootstrap(run_id) do
      {:ok, snapshot(run_id)}
    end
  end

  def bootstrap(run_id) do
    with :ok <- ensure_exists(run_id) do
      GenServer.call(via(run_id), :bootstrap)
    end
  end

  def snapshot(run_id) do
    case ensure_exists(run_id) do
      :ok -> GenServer.call(via(run_id), :snapshot)
      {:error, :not_found} -> load_persisted(run_id)
    end
  end

  def task_list(run_id) do
    case ensure_exists(run_id) do
      :ok -> GenServer.call(via(run_id), :task_list)
      {:error, :not_found} -> load_persisted_tasks(run_id)
    end
  end

  def worker_snapshots(run_id) do
    with :ok <- ensure_exists(run_id) do
      GenServer.call(via(run_id), :worker_snapshots)
    end
  end

  def stop(run_id) do
    with :ok <- ensure_exists(run_id) do
      GenServer.stop(via(run_id), :normal)
    end
  end

  def list_run_ids do
    Registry.select(Beamwarden.RunRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def all_worker_snapshots do
    list_run_ids()
    |> Enum.flat_map(fn run_id ->
      case worker_snapshots(run_id) do
        snapshots when is_list(snapshots) -> snapshots
        _ -> []
      end
    end)
  end

  def wait_for_completion(run_id, attempts \\ 80)

  def wait_for_completion(run_id, 0), do: snapshot(run_id)

  def wait_for_completion(run_id, attempts) do
    case snapshot(run_id) do
      %{status: status} = snapshot when status in ["completed", "failed"] ->
        snapshot

      _ ->
        Process.sleep(25)
        wait_for_completion(run_id, attempts - 1)
    end
  end

  @impl true
  def init(opts) do
    prompt = Keyword.fetch!(opts, :prompt)
    worker_count = max(Keyword.fetch!(opts, :workers), 1)
    now = now_ms()

    {:ok,
     %__MODULE__{
       run_id: Keyword.fetch!(opts, :run_id),
       prompt: prompt,
       worker_count: worker_count,
       tasks: TaskScheduler.build_tasks(prompt, worker_count),
       created_at: now,
       updated_at: now
     }}
  end

  @impl true
  def handle_call(:bootstrap, _from, %__MODULE__{workers: workers} = state)
      when map_size(workers) > 0 do
    {:reply, :ok, state}
  end

  def handle_call(:bootstrap, _from, %__MODULE__{} = state) do
    worker_ids =
      for idx <- 1..state.worker_count do
        worker_id = "#{state.run_id}-worker-#{idx}"

        {:ok, _pid} =
          DynamicSupervisor.start_child(
            Beamwarden.WorkerSupervisor,
            {ExternalWorker, worker_id: worker_id, run_id: state.run_id, manager: self()}
          )

        {worker_id,
         %{worker_id: worker_id, run_id: state.run_id, state: "idle", current_task_id: nil}}
      end

    next_state =
      state
      |> Map.put(:workers, Map.new(worker_ids))
      |> Map.put(:status, "running")
      |> touch()
      |> assign_pending_tasks()
      |> persist()

    {:reply, :ok, next_state}
  end

  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, render_snapshot(state), state}
  end

  def handle_call(:task_list, _from, %__MODULE__{} = state) do
    {:reply, state.tasks, state}
  end

  def handle_call(:worker_snapshots, _from, %__MODULE__{} = state) do
    {:reply, Map.values(state.workers), state}
  end

  @impl true
  def handle_info({:worker_result, worker_id, task_id, {:ok, summary}}, %__MODULE__{} = state) do
    next_state =
      state
      |> put_worker(worker_id, %{state: "idle", current_task_id: nil, last_result: summary})
      |> Map.put(:tasks, TaskScheduler.complete_task(state.tasks, task_id, summary))
      |> touch()
      |> assign_pending_tasks()
      |> maybe_finish()
      |> persist()

    {:noreply, next_state}
  end

  def handle_info({:worker_result, worker_id, task_id, {:error, error}}, %__MODULE__{} = state) do
    next_state =
      state
      |> put_worker(worker_id, %{state: "idle", current_task_id: nil, error: error})
      |> Map.put(:tasks, TaskScheduler.fail_task(state.tasks, task_id, error))
      |> touch()
      |> assign_pending_tasks()
      |> maybe_finish()
      |> persist()

    {:noreply, next_state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    Enum.each(Map.keys(state.workers), fn worker_id ->
      _ = ExternalWorker.stop(worker_id)
    end)

    :ok
  end

  defp assign_pending_tasks(%__MODULE__{} = state) do
    Enum.reduce(state.workers, state, fn {worker_id, worker}, acc ->
      task = TaskScheduler.next_pending_task(acc.tasks)

      cond do
        worker.state != "idle" ->
          acc

        is_nil(task) ->
          acc

        true ->
          :ok = ExternalWorker.assign(worker_id, task)

          acc
          |> Map.put(:tasks, TaskScheduler.assign_task(acc.tasks, task.id, worker_id))
          |> put_worker(worker_id, %{state: "running", current_task_id: task.id})
      end
    end)
  end

  defp maybe_finish(%__MODULE__{} = state) do
    counts = TaskScheduler.counts(state.tasks)

    cond do
      counts.pending > 0 or counts.running > 0 ->
        state

      counts.failed > 0 ->
        %{state | status: "failed"}

      true ->
        %{state | status: "completed"}
    end
  end

  defp put_worker(%__MODULE__{} = state, worker_id, attrs) do
    update_in(state.workers[worker_id], fn worker ->
      worker
      |> Map.merge(attrs)
      |> Map.put(:run_id, state.run_id)
      |> Map.put(:worker_id, worker_id)
    end)
  end

  defp render_snapshot(%__MODULE__{} = state) do
    counts = TaskScheduler.counts(state.tasks)

    %{
      run_id: state.run_id,
      prompt: state.prompt,
      status: state.status,
      worker_count: map_size(state.workers),
      task_counts: counts,
      created_at: state.created_at,
      updated_at: state.updated_at
    }
  end

  defp touch(%__MODULE__{} = state), do: %{state | updated_at: now_ms()}

  defp persist(%__MODULE__{} = state) do
    Beamwarden.run_root()
    |> File.mkdir_p!()

    payload =
      state
      |> render_snapshot()
      |> Map.put(:tasks, state.tasks)
      |> Map.put(:workers, Map.values(state.workers))

    Beamwarden.run_path(state.run_id)
    |> File.write!(JSON.encode!(payload))

    state
  end

  defp via(run_id), do: {:via, Registry, {Beamwarden.RunRegistry, run_id}}

  defp ensure_exists(run_id) do
    case Registry.lookup(Beamwarden.RunRegistry, run_id) do
      [{_pid, _value}] -> :ok
      [] -> {:error, :not_found}
    end
  end

  defp load_persisted(run_id) do
    path = Beamwarden.run_path(run_id)

    if File.exists?(path) do
      {:ok, JSON.decode!(File.read!(path))}
      |> case do
        {:ok, snapshot} -> snapshot
      end
    else
      {:error, :not_found}
    end
  end

  defp load_persisted_tasks(run_id) do
    case load_persisted(run_id) do
      %{"tasks" => tasks} -> tasks
      {:error, :not_found} -> {:error, :not_found}
      _ -> []
    end
  end

  defp generate_run_id do
    "run-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp now_ms, do: System.system_time(:millisecond)
end
