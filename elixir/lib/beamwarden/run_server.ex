defmodule Beamwarden.RunServer do
  @moduledoc false

  use GenServer

  defstruct [
    :run_id,
    :prompt,
    :created_at,
    :updated_at,
    tasks: [],
    workers: %{},
    requested_workers: 1,
    status: "pending"
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

  def start_run(prompt, opts \\ []) do
    run_id = Keyword.get(opts, :run_id, unique_run_id())

    child_opts =
      opts
      |> Keyword.put(:run_id, run_id)
      |> Keyword.put(:prompt, prompt)
      |> Keyword.put_new(:workers, 1)

    with {:ok, _pid} <-
           DynamicSupervisor.start_child(Beamwarden.RunSupervisor, {__MODULE__, child_opts}) do
      {:ok, snapshot(run_id)}
    end
  end

  def snapshot(run_id) do
    GenServer.call(via(run_id), :snapshot)
  end

  def list_tasks(run_id) do
    GenServer.call(via(run_id), :tasks)
  end

  def list_runs do
    Beamwarden.RunRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(&snapshot/1)
    |> Enum.sort_by(& &1.run_id)
  end

  def stop(run_id) do
    case Registry.lookup(Beamwarden.RunRegistry, run_id) do
      [{pid, _value}] -> GenServer.call(pid, :stop, :infinity)
      [] -> :ok
    end
  end

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    prompt = Keyword.fetch!(opts, :prompt)
    requested_workers = max(Keyword.get(opts, :workers, 1), 1)
    now = timestamp()
    tasks = Beamwarden.TaskScheduler.initial_tasks(run_id, prompt)

    state = %__MODULE__{
      run_id: run_id,
      prompt: prompt,
      created_at: now,
      updated_at: now,
      tasks: tasks,
      requested_workers: requested_workers,
      status: Beamwarden.TaskScheduler.run_status(tasks)
    }

    state =
      Enum.reduce(1..requested_workers, state, fn index, acc ->
        worker_id = "#{run_id}-worker-#{index}"

        {:ok, _pid} =
          Beamwarden.WorkerSupervisor.start_worker(
            worker_id: worker_id,
            run_id: run_id,
            run_pid: self()
          )

        put_in(acc.workers[worker_id], %{state: "idle", current_task_id: nil})
      end)
      |> dispatch()

    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, snapshot_map(state), state}
  end

  def handle_call(:tasks, _from, %__MODULE__{} = state) do
    {:reply, Enum.sort_by(state.tasks, &String.to_integer(&1.task_id)), state}
  end

  def handle_call(:stop, _from, %__MODULE__{} = state) do
    Enum.each(Map.keys(state.workers), &Beamwarden.ExternalWorker.stop/1)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:worker_result, worker_id, task_id, result}, %__MODULE__{} = state) do
    tasks = Beamwarden.TaskScheduler.finish_task(state.tasks, task_id, worker_id, result)

    state =
      state
      |> Map.put(:tasks, tasks)
      |> put_in([Access.key(:workers), worker_id], %{state: "idle", current_task_id: nil})
      |> touch()
      |> dispatch()

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp dispatch(%__MODULE__{} = state) do
    case next_idle_worker(state) do
      nil ->
        finalize(state)

      worker_id ->
        case Beamwarden.TaskScheduler.assign_next_task(state.tasks, worker_id) do
          {:none, _tasks} ->
            finalize(state)

          {task, tasks} ->
            Beamwarden.ExternalWorker.run_task(worker_id, task)

            state
            |> Map.put(:tasks, tasks)
            |> put_in([Access.key(:workers), worker_id], %{
              state: "running",
              current_task_id: task.task_id
            })
            |> touch()
            |> dispatch()
        end
    end
  end

  defp finalize(%__MODULE__{} = state) do
    %{state | status: Beamwarden.TaskScheduler.run_status(state.tasks), updated_at: timestamp()}
  end

  defp next_idle_worker(%__MODULE__{} = state) do
    state.workers
    |> Enum.find_value(fn {worker_id, worker} ->
      if worker.state == "idle", do: worker_id, else: nil
    end)
  end

  defp snapshot_map(%__MODULE__{} = state) do
    counts = Beamwarden.TaskScheduler.counts(state.tasks)

    %{
      run_id: state.run_id,
      prompt: state.prompt,
      status: Beamwarden.TaskScheduler.run_status(state.tasks),
      created_at: state.created_at,
      updated_at: state.updated_at,
      task_ids: Enum.map(state.tasks, & &1.task_id),
      worker_ids: Map.keys(state.workers) |> Enum.sort(),
      worker_count: map_size(state.workers),
      requested_workers: state.requested_workers,
      task_count: counts.task_count,
      pending_count: counts.pending_count,
      running_count: counts.running_count,
      completed_count: counts.completed_count,
      failed_count: counts.failed_count
    }
  end

  defp touch(%__MODULE__{} = state) do
    %{state | status: Beamwarden.TaskScheduler.run_status(state.tasks), updated_at: timestamp()}
  end

  defp unique_run_id do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "run-#{suffix}"
  end

  defp via(run_id), do: {:via, Registry, {Beamwarden.RunRegistry, run_id}}

  defp timestamp do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
