defmodule Beamwarden.RunServer do
  @moduledoc false

  use GenServer

  alias Beamwarden.TaskScheduler

  defstruct [:run_id, :prompt, :created_at, :updated_at, :worker_opts, tasks: [], worker_ids: []]

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

  def snapshot(run_id) do
    GenServer.call(via(run_id), :snapshot)
  end

  def running?(run_id) do
    Registry.lookup(Beamwarden.RunRegistry, run_id) != []
  end

  def worker_result(run_id, worker_id, task_id, result) do
    GenServer.cast(via(run_id), {:worker_result, worker_id, task_id, result})
  end

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    prompt = Keyword.fetch!(opts, :prompt)
    worker_count = max(Keyword.get(opts, :workers, 1), 0)
    now = now()

    state = %__MODULE__{
      run_id: run_id,
      prompt: prompt,
      tasks: TaskScheduler.build_initial_tasks(run_id, prompt),
      created_at: now,
      updated_at: now,
      worker_opts: Keyword.get(opts, :worker_opts, [])
    }

    worker_ids =
      if worker_count > 0 do
        Enum.map(1..worker_count, fn index ->
          {:ok, worker_id} =
            Beamwarden.WorkerSupervisor.start_worker(
              run_id,
              Keyword.merge(state.worker_opts, worker_id: "#{run_id}-worker-#{index}")
            )

          worker_id
        end)
      else
        []
      end

    next_state = persist(%{state | worker_ids: worker_ids})
    send(self(), :dispatch)
    {:ok, next_state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, snapshot_map(state), state}
  end

  @impl true
  def handle_cast({:worker_result, worker_id, task_id, {:ok, summary}}, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.put(:tasks, TaskScheduler.complete_task(state.tasks, task_id, worker_id, summary))
      |> Map.put(:updated_at, now())
      |> persist()

    send(self(), :dispatch)
    {:noreply, next_state}
  end

  @impl true
  def handle_cast({:worker_result, worker_id, task_id, {:error, error}}, %__MODULE__{} = state) do
    next_state =
      state
      |> Map.put(:tasks, TaskScheduler.fail_task(state.tasks, task_id, worker_id, error))
      |> Map.put(:updated_at, now())
      |> persist()

    send(self(), :dispatch)
    {:noreply, next_state}
  end

  @impl true
  def handle_info(:dispatch, %__MODULE__{} = state) do
    {tasks, assigned?} =
      Beamwarden.WorkerSupervisor.list_live_workers(run_id: state.run_id)
      |> Enum.filter(&(value(&1, :state) == "idle"))
      |> Enum.reduce({state.tasks, false}, fn worker, {tasks, assigned?} ->
        worker_id = value(worker, :worker_id)

        case TaskScheduler.assign_next_task(tasks, worker_id) do
          {:ok, task, updated_tasks} ->
            Beamwarden.ExternalWorker.assign(worker_id, task)
            {updated_tasks, true}

          :none ->
            {tasks, assigned?}
        end
      end)

    next_state =
      if assigned? do
        state
        |> Map.put(:tasks, tasks)
        |> Map.put(:updated_at, now())
        |> persist()
      else
        state
      end

    {:noreply, next_state}
  end

  defp persist(%__MODULE__{} = state) do
    snapshot = snapshot_map(state)
    Beamwarden.RunStore.save(snapshot)
    %{state | updated_at: value(snapshot, :updated_at)}
  end

  defp snapshot_map(%__MODULE__{} = state) do
    counts = TaskScheduler.counts(state.tasks)

    %{
      run_id: state.run_id,
      prompt: state.prompt,
      status: TaskScheduler.status(state.tasks, length(state.worker_ids)),
      created_at: state.created_at,
      updated_at: state.updated_at || now(),
      task_ids: Enum.map(state.tasks, &value(&1, :task_id)),
      worker_ids: state.worker_ids,
      tasks: Enum.map(state.tasks, &normalize_task/1),
      task_count: counts.task_count,
      pending_count: counts.pending_count,
      running_count: counts.running_count,
      completed_count: counts.completed_count,
      failed_count: counts.failed_count
    }
  end

  defp normalize_task(task) do
    %{
      task_id: value(task, :task_id),
      run_id: value(task, :run_id),
      title: value(task, :title),
      payload: value(task, :payload),
      status: value(task, :status),
      assigned_worker: value(task, :assigned_worker),
      result_summary: value(task, :result_summary),
      error: value(task, :error),
      created_at: value(task, :created_at),
      updated_at: value(task, :updated_at)
    }
  end

  defp via(run_id), do: {:via, Registry, {Beamwarden.RunRegistry, run_id}}
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
