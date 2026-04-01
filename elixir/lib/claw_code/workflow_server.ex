defmodule ClawCode.WorkflowServer do
  @moduledoc false

  use GenServer

  defstruct [:workflow_id, steps: [], persisted_workflow_path: nil]

  def child_spec(workflow_id) do
    %{
      id: {__MODULE__, workflow_id},
      start: {__MODULE__, :start_link, [workflow_id]},
      restart: :transient
    }
  end

  def start_link(workflow_id) do
    GenServer.start_link(__MODULE__, workflow_id, name: via(workflow_id))
  end

  def add_step(workflow_id, title, description \\ nil) do
    GenServer.call(via(workflow_id), {:add_step, title, description})
  end

  def complete_step(workflow_id, step_id) do
    GenServer.call(via(workflow_id), {:complete_step, step_id})
  end

  def transition_step(workflow_id, step_id, status, detail \\ nil) do
    GenServer.call(via(workflow_id), {:transition_step, step_id, status, detail})
  end

  def snapshot(workflow_id) do
    GenServer.call(via(workflow_id), :snapshot)
  end

  def stop(workflow_id) do
    GenServer.stop(via(workflow_id), :normal)
  end

  @impl true
  def init(workflow_id) do
    state =
      case ClawCode.WorkflowStore.load(workflow_id) do
        {:ok, snapshot} ->
          %__MODULE__{
            workflow_id: workflow_id,
            steps: snapshot["steps"] || [],
            persisted_workflow_path: ClawCode.workflow_path(workflow_id)
          }

        :error ->
          %__MODULE__{workflow_id: workflow_id}
      end

    state =
      if state.persisted_workflow_path do
        state
      else
        persist(state)
      end

    ClawCode.ClusterDaemon.claim_local_owner(
      :workflow,
      workflow_id,
      persisted_path: state.persisted_workflow_path
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:add_step, title, description}, _from, %__MODULE__{} = state) do
    step = %{
      "id" => "#{length(state.steps) + 1}",
      "title" => title,
      "description" => description,
      "status" => "pending"
    }

    next_state = persist(%{state | steps: state.steps ++ [step]})
    {:reply, snapshot_map(next_state), next_state}
  end

  @impl true
  def handle_call({:complete_step, step_id}, _from, %__MODULE__{} = state) do
    steps =
      Enum.map(state.steps, fn step ->
        if step["id"] == step_id, do: Map.put(step, "status", "completed"), else: step
      end)

    next_state = persist(%{state | steps: steps})
    {:reply, snapshot_map(next_state), next_state}
  end

  @impl true
  def handle_call({:transition_step, step_id, status, detail}, _from, %__MODULE__{} = state) do
    steps =
      Enum.map(state.steps, fn step ->
        if step["id"] == step_id do
          step
          |> Map.put("status", status)
          |> maybe_put_description(detail)
        else
          step
        end
      end)

    next_state = persist(%{state | steps: steps})
    {:reply, snapshot_map(next_state), next_state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, snapshot_map(state), state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{workflow_id: workflow_id}) do
    safe_cluster_update(fn -> ClawCode.ClusterDaemon.mark_stopped(:workflow, workflow_id) end)
    :ok
  end

  defp persist(%__MODULE__{} = state) do
    path = ClawCode.WorkflowStore.save(snapshot_map(state))
    safe_cluster_update(fn -> ClawCode.ClusterDaemon.note_persisted(:workflow, state.workflow_id, path) end)
    %{state | persisted_workflow_path: path}
  end

  defp snapshot_map(%__MODULE__{} = state) do
    %{
      workflow_id: state.workflow_id,
      steps: state.steps,
      owner_node: ClawCode.Cluster.local_owner_label(),
      persisted_workflow_path: state.persisted_workflow_path
    }
  end

  defp maybe_put_description(step, nil), do: step
  defp maybe_put_description(step, detail), do: Map.put(step, "description", detail)

  defp via(workflow_id), do: {:via, Registry, {ClawCode.WorkflowRegistry, workflow_id}}

  defp safe_cluster_update(fun) do
    fun.()
  catch
    :exit, _reason -> :ok
  end
end
