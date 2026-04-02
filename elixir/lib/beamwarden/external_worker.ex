defmodule Beamwarden.ExternalWorker do
  @moduledoc false

  use GenServer

  defstruct [
    :worker_id,
    :run_id,
    :run_pid,
    :current_task_id,
    :runner_ref,
    :runner_pid,
    :started_at,
    :heartbeat_at,
    :last_event_at,
    :last_result_summary,
    :last_exit_status,
    state: "idle"
  ]

  def child_spec(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)

    %{
      id: {__MODULE__, worker_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)
    GenServer.start_link(__MODULE__, opts, name: via(worker_id))
  end

  def run_task(worker_id, task) do
    GenServer.cast(via(worker_id), {:run_task, task})
  end

  def snapshot(worker_id) do
    GenServer.call(via(worker_id), :snapshot)
  end

  def list_workers do
    Beamwarden.WorkerRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(&snapshot/1)
    |> Enum.sort_by(&{&1.run_id, &1.worker_id})
  end

  def stop(worker_id) do
    case Registry.lookup(Beamwarden.WorkerRegistry, worker_id) do
      [{pid, _value}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  @impl true
  def init(opts) do
    now = timestamp()

    {:ok,
     %__MODULE__{
       worker_id: Keyword.fetch!(opts, :worker_id),
       run_id: Keyword.fetch!(opts, :run_id),
       run_pid: Keyword.fetch!(opts, :run_pid),
       started_at: now,
       heartbeat_at: now,
       last_event_at: now
     }}
  end

  @impl true
  def handle_cast({:run_task, task}, %__MODULE__{state: "idle"} = state) do
    owner = self()
    command = worker_command()
    env = worker_env(state, task)
    task_id = task.task_id

    {runner_pid, runner_ref} =
      spawn_monitor(fn ->
        result = execute(command, env)
        send(owner, {:worker_exec_done, task_id, result})
      end)

    now = timestamp()

    {:noreply,
     %{
       state
       | state: "running",
         current_task_id: task_id,
         runner_pid: runner_pid,
         runner_ref: runner_ref,
         heartbeat_at: now,
         last_event_at: now
     }}
  end

  def handle_cast({:run_task, _task}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, snapshot_map(state), state}
  end

  @impl true
  def handle_info({:worker_exec_done, task_id, result}, %__MODULE__{} = state) do
    send(state.run_pid, {:worker_result, state.worker_id, task_id, result})
    now = timestamp()

    next_state =
      case result do
        {:ok, summary} ->
          %{
            state
            | state: "idle",
              current_task_id: nil,
              runner_pid: nil,
              runner_ref: nil,
              last_result_summary: summary,
              last_exit_status: 0,
              heartbeat_at: now,
              last_event_at: now
          }

        {:error, summary} ->
          %{
            state
            | state: "idle",
              current_task_id: nil,
              runner_pid: nil,
              runner_ref: nil,
              last_result_summary: summary,
              last_exit_status: 1,
              heartbeat_at: now,
              last_event_at: now
          }
      end

    {:noreply, next_state}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, %__MODULE__{runner_ref: ref} = state) do
    {:noreply, %{state | runner_ref: nil, runner_pid: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{runner_ref: ref} = state) do
    summary = "worker crashed: #{inspect(reason)}"

    send(
      state.run_pid,
      {:worker_result, state.worker_id, state.current_task_id, {:error, summary}}
    )

    now = timestamp()

    {:noreply,
     %{
       state
       | state: "idle",
         current_task_id: nil,
         runner_pid: nil,
         runner_ref: nil,
         last_result_summary: summary,
         last_exit_status: 1,
         heartbeat_at: now,
         last_event_at: now
     }}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp snapshot_map(%__MODULE__{} = state) do
    %{
      worker_id: state.worker_id,
      run_id: state.run_id,
      state: state.state,
      current_task_id: state.current_task_id,
      started_at: state.started_at,
      heartbeat_at: state.heartbeat_at,
      last_event_at: state.last_event_at,
      last_result_summary: state.last_result_summary,
      last_exit_status: state.last_exit_status
    }
  end

  defp via(worker_id), do: {:via, Registry, {Beamwarden.WorkerRegistry, worker_id}}

  defp worker_command do
    case Beamwarden.AppIdentity.get_env(:orchestrator_worker_command) do
      {cmd, args} when is_binary(cmd) and is_list(args) -> {cmd, args}
      %{cmd: cmd, args: args} when is_binary(cmd) and is_list(args) -> {cmd, args}
      _ -> {"/bin/sh", ["-lc", "printf 'processed:%s\\n' \"$BW_TASK_PAYLOAD\""]}
    end
  end

  defp worker_env(state, task) do
    [
      {"BW_RUN_ID", state.run_id},
      {"BW_WORKER_ID", state.worker_id},
      {"BW_TASK_ID", task.task_id},
      {"BW_TASK_PAYLOAD", task.payload}
    ]
  end

  defp execute({command, args}, env) do
    try do
      case System.cmd(command, args, env: env, stderr_to_stdout: true) do
        {output, 0} -> {:ok, normalize_output(output, "ok")}
        {output, status} -> {:error, normalize_output(output, "exit=#{status}")}
      end
    rescue
      error -> {:error, "worker execution failed: #{Exception.message(error)}"}
    end
  end

  defp normalize_output(output, fallback) do
    case output |> to_string() |> String.trim() do
      "" -> fallback
      text -> text
    end
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
