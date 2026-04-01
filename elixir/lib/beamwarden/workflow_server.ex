defmodule Beamwarden.WorkflowServer do
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
    state = restore_state(workflow_id)

    state =
      if state.persisted_workflow_path do
        state
      else
        persist(state)
      end

    Beamwarden.ClusterDaemon.claim_local_owner(
      :workflow,
      workflow_id,
      persisted_path: state.persisted_workflow_path
    )

    persist_runtime_snapshot(state)

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
  def terminate(_reason, %__MODULE__{} = state) do
    safe_cluster_update(fn -> persist_runtime_snapshot(state) end)
    workflow_id = state.workflow_id
    safe_cluster_update(fn -> Beamwarden.ClusterDaemon.mark_stopped(:workflow, workflow_id) end)
    :ok
  end

  defp persist(%__MODULE__{} = state) do
    path = Beamwarden.WorkflowStore.save(snapshot_map(state))

    safe_cluster_update(fn ->
      Beamwarden.ClusterDaemon.note_persisted(:workflow, state.workflow_id, path)
    end)

    next_state = %{state | persisted_workflow_path: path}
    persist_runtime_snapshot(next_state)
    next_state
  end

  defp snapshot_map(%__MODULE__{} = state) do
    %{
      workflow_id: state.workflow_id,
      steps: state.steps,
      owner_node: Beamwarden.Cluster.local_owner_label(),
      persisted_workflow_path: state.persisted_workflow_path
    }
  end

  defp maybe_put_description(step, nil), do: step
  defp maybe_put_description(step, detail), do: Map.put(step, "description", detail)

  defp via(workflow_id), do: {:via, Registry, {Beamwarden.WorkflowRegistry, workflow_id}}

  defp restore_state(workflow_id) do
    case Beamwarden.ClusterDaemon.runtime_snapshot(:workflow, workflow_id) do
      snapshot when is_map(snapshot) ->
        %__MODULE__{
          workflow_id: workflow_id,
          steps: runtime_value(snapshot, :steps) || [],
          persisted_workflow_path:
            runtime_value(snapshot, :persisted_workflow_path) ||
              existing_persisted_path(workflow_id)
        }

      _ ->
        case Beamwarden.WorkflowStore.load(workflow_id) do
          {:ok, snapshot} ->
            %__MODULE__{
              workflow_id: workflow_id,
              steps: snapshot["steps"] || [],
              persisted_workflow_path: Beamwarden.workflow_path(workflow_id)
            }

          :error ->
            %__MODULE__{workflow_id: workflow_id}
        end
    end
  end

  defp persist_runtime_snapshot(%__MODULE__{} = state) do
    Beamwarden.ClusterDaemon.persist_runtime_snapshot(
      :workflow,
      state.workflow_id,
      runtime_snapshot(state)
    )

    :ok
  end

  defp runtime_snapshot(%__MODULE__{} = state) do
    %{
      workflow_id: state.workflow_id,
      steps: state.steps,
      persisted_workflow_path: state.persisted_workflow_path
    }
  end

  defp runtime_value(snapshot, key) do
    Map.get(snapshot, key) || Map.get(snapshot, Atom.to_string(key))
  end

  defp existing_persisted_path(workflow_id) do
    if File.exists?(Beamwarden.workflow_path(workflow_id)),
      do: Beamwarden.workflow_path(workflow_id),
      else: nil
  end

  defp safe_cluster_update(fun) do
    fun.()
  catch
    :exit, _reason -> :ok
  end
end
