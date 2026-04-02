defmodule Beamwarden.ExternalWorker do
  @moduledoc false

  use GenServer

  defstruct [:worker_id, :run_id, :manager, :task_ref, :current_task_id, state: :idle]

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

  def assign(worker_id, task) do
    GenServer.call(via(worker_id), {:assign, task})
  end

  def snapshot(worker_id) do
    GenServer.call(via(worker_id), :snapshot)
  end

  def stop(worker_id) do
    GenServer.stop(via(worker_id), :normal)
  end

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       worker_id: Keyword.fetch!(opts, :worker_id),
       run_id: Keyword.fetch!(opts, :run_id),
       manager: Keyword.fetch!(opts, :manager)
     }}
  end

  @impl true
  def handle_call({:assign, _task}, _from, %__MODULE__{state: :running} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:assign, task}, _from, %__MODULE__{} = state) do
    async = Task.async(fn -> execute_task(task) end)

    next_state = %{
      state
      | state: :running,
        task_ref: async.ref,
        current_task_id: task.id
    }

    {:reply, :ok, next_state}
  end

  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply,
     %{
       worker_id: state.worker_id,
       run_id: state.run_id,
       state: Atom.to_string(state.state),
       current_task_id: state.current_task_id
     }, state}
  end

  @impl true
  def handle_info({ref, result}, %__MODULE__{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    send_result(state, result)
    {:noreply, reset(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{task_ref: ref} = state) do
    send_result(state, {:error, "worker crashed: #{inspect(reason)}"})
    {:noreply, reset(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp execute_task(task) do
    shell = System.find_executable("sh") || "/bin/sh"

    {output, status} =
      System.cmd(shell, ["-lc", "printf '%s\\n' \"$BEAMWARDEN_TASK_TITLE\""],
        env: [
          {"BEAMWARDEN_TASK_TITLE", task.title}
        ]
      )

    if status == 0 do
      {:ok, String.trim(output)}
    else
      {:error, String.trim(output)}
    end
  end

  defp send_result(%__MODULE__{} = state, result) do
    send(state.manager, {:worker_result, state.worker_id, state.current_task_id, result})
  end

  defp reset(%__MODULE__{} = state) do
    %{state | state: :idle, task_ref: nil, current_task_id: nil}
  end

  defp via(worker_id) do
    {:via, Registry, {Beamwarden.OrchestratorWorkerRegistry, worker_id}}
  end
end
