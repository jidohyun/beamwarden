defmodule ClawCode.ControlPlane do
  @moduledoc false

  alias ClawCode.{Cluster, PortingTask}

  def ensure_session(session_id) do
    target = resolve_session_node(session_id)

    with {:ok, result} <- call_node(target, :ensure_local_session, [session_id]) do
      result
    end
  end

  def ensure_local_session(session_id) do
    case Registry.lookup(ClawCode.SessionRegistry, session_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          ClawCode.SessionSupervisor,
          {ClawCode.SessionServer, session_id}
        )
        |> normalize_start()
    end
  end

  def submit_prompt(session_id, prompt) do
    target = resolve_session_node(session_id)

    with {:ok, result} <- call_node(target, :submit_prompt_local, [session_id, prompt]) do
      result
    end
  end

  def session_snapshot(session_id) do
    target = resolve_session_node(session_id)

    with {:ok, result} <- call_node(target, :session_snapshot_local, [session_id]) do
      result
    end
  end

  def submit_session(session_id, prompt, _opts \\ []) do
    with {:ok, snapshot} <- submit_prompt(session_id, prompt) do
      {:ok,
       %{
         text: snapshot.last_result || "",
         session_id: snapshot.session_id,
         stop_reason: snapshot.stop_reason || "completed",
         matched_commands: [],
         matched_tools: []
       }}
    end
  end

  def ensure_workflow(workflow_id) do
    target = resolve_workflow_node(workflow_id)

    with {:ok, result} <- call_node(target, :ensure_local_workflow, [workflow_id]) do
      result
    end
  end

  def ensure_local_workflow(workflow_id) do
    case Registry.lookup(ClawCode.WorkflowRegistry, workflow_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          ClawCode.WorkflowSupervisor,
          {ClawCode.WorkflowServer, workflow_id}
        )
        |> normalize_start()
    end
  end

  def add_workflow_step(workflow_id, title, description \\ nil) do
    target = resolve_workflow_node(workflow_id)

    with {:ok, result} <- call_node(target, :add_workflow_step_local, [workflow_id, title, description]) do
      result
    end
  end

  def complete_workflow_step(workflow_id, step_id) do
    target = resolve_workflow_node(workflow_id)

    with {:ok, result} <- call_node(target, :complete_workflow_step_local, [workflow_id, step_id]) do
      result
    end
  end

  def workflow_snapshot(workflow_id) do
    target = resolve_workflow_node(workflow_id)

    with {:ok, result} <- call_node(target, :workflow_snapshot_local, [workflow_id]) do
      result
    end
  end

  def start_workflow(workflow_id, tasks \\ []) do
    target = resolve_workflow_node(workflow_id)

    with {:ok, result} <- call_node(target, :start_workflow_local, [workflow_id, tasks]) do
      result
    end
  end

  def advance_task(workflow_id, task_id, status, detail \\ nil) do
    target = resolve_workflow_node(workflow_id)

    with {:ok, result} <-
           call_node(target, :advance_task_local, [workflow_id, task_id, status, detail]) do
      result
    end
  end

  def list_sessions do
    Cluster.member_nodes()
    |> Enum.flat_map(fn target ->
      case call_node(target, :list_local_sessions, []) do
        {:ok, snapshots} when is_list(snapshots) -> snapshots
        {:error, _reason} -> []
      end
    end)
    |> Enum.uniq_by(& &1.session_id)
  end

  def list_workflows do
    Cluster.member_nodes()
    |> Enum.flat_map(fn target ->
      case call_node(target, :list_local_workflows, []) do
        {:ok, snapshots} when is_list(snapshots) -> snapshots
        {:error, _reason} -> []
      end
    end)
    |> Enum.uniq_by(& &1.workflow_id)
  end

  def status_report do
    cluster = Cluster.status()
    sessions = list_sessions()
    workflows = list_workflows()

    [
      "# OTP Control Plane",
      "",
      "Cluster mode: #{if(cluster.distributed?, do: "distributed", else: "single-node")}",
      "Cluster members: #{Enum.map_join(cluster.members, ", ", &Atom.to_string/1)}",
      "Routing: #{cluster.routing_strategy}",
      "",
      "Sessions: #{length(sessions)}",
      "Workflows: #{length(workflows)}",
      "",
      if(sessions == [],
        do: "No supervised sessions",
        else:
          Enum.map(
            sessions,
            &"session=#{&1.session_id} node=#{&1.owner_node || "local"} turns=#{&1.turns}"
          )
      ),
      "",
      if(workflows == [],
        do: "No supervised workflows",
        else:
          Enum.map(
            workflows,
            &"workflow=#{&1.workflow_id} node=#{&1.owner_node || "local"} steps=#{length(&1.steps)}"
          )
      )
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def render_session(snapshot) when is_map(snapshot) do
    [
      "Session Snapshot",
      "",
      "session_id=#{snapshot.session_id}",
      "turns=#{snapshot.turns}",
      "submits=#{snapshot.submits || snapshot.turns}",
      "stop_reason=#{snapshot.stop_reason || "none"}",
      "owner_node=#{snapshot.owner_node || "local"}",
      "persisted_session_path=#{snapshot.persisted_session_path || "none"}",
      if(snapshot.last_result, do: "last_result=#{snapshot.last_result}", else: nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def render_workflow(snapshot) when is_map(snapshot) do
    [
      "Workflow Snapshot",
      "",
      "workflow_id=#{snapshot.workflow_id}",
      "name=#{snapshot.workflow_id}",
      "status=#{workflow_status(snapshot.steps)}",
      "owner_node=#{snapshot.owner_node || "local"}",
      "task_count=#{length(snapshot.steps)}",
      "tasks:",
      Enum.map(snapshot.steps, &task_line/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def submit_prompt_local(session_id, prompt) do
    with {:ok, _pid} <- ensure_local_session(session_id) do
      {:ok, ClawCode.SessionServer.submit(session_id, prompt)}
    end
  end

  def session_snapshot_local(session_id) do
    with {:ok, _pid} <- ensure_local_session(session_id) do
      {:ok, ClawCode.SessionServer.snapshot(session_id)}
    end
  end

  def list_local_sessions do
    ClawCode.SessionRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(&ClawCode.SessionServer.snapshot/1)
  end

  def add_workflow_step_local(workflow_id, title, description \\ nil) do
    with {:ok, _pid} <- ensure_local_workflow(workflow_id) do
      {:ok, ClawCode.WorkflowServer.add_step(workflow_id, title, description)}
    end
  end

  def complete_workflow_step_local(workflow_id, step_id) do
    with {:ok, _pid} <- ensure_local_workflow(workflow_id) do
      {:ok, ClawCode.WorkflowServer.complete_step(workflow_id, step_id)}
    end
  end

  def workflow_snapshot_local(workflow_id) do
    with {:ok, _pid} <- ensure_local_workflow(workflow_id) do
      {:ok, ClawCode.WorkflowServer.snapshot(workflow_id)}
    end
  end

  def start_workflow_local(workflow_id, tasks \\ []) do
    with {:ok, _pid} <- ensure_local_workflow(workflow_id) do
      Enum.each(tasks, fn
        %PortingTask{} = task ->
          ClawCode.WorkflowServer.add_step(workflow_id, task.title || task.id, task.description)

        description when is_binary(description) ->
          ClawCode.WorkflowServer.add_step(workflow_id, description)
      end)

      workflow_snapshot_local(workflow_id)
    end
  end

  def advance_task_local(workflow_id, task_id, status, detail \\ nil) do
    with {:ok, _pid} <- ensure_local_workflow(workflow_id) do
      {:ok, ClawCode.WorkflowServer.transition_step(workflow_id, task_id, status, detail)}
    end
  end

  def list_local_workflows do
    ClawCode.WorkflowRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(&ClawCode.WorkflowServer.snapshot/1)
  end

  def session_route_node(session_id), do: resolve_session_node(session_id)
  def workflow_route_node(workflow_id), do: resolve_workflow_node(workflow_id)

  defp workflow_status(steps) do
    cond do
      Enum.any?(steps, &(&1["status"] == "failed")) -> "failed"
      steps != [] and Enum.all?(steps, &(&1["status"] == "completed")) -> "completed"
      Enum.any?(steps, &(&1["status"] == "in_progress")) -> "in_progress"
      true -> "pending"
    end
  end

  defp task_line(step) do
    base = "[#{step["status"]}] #{step["id"]} — #{step["title"]}"

    case step["description"] do
      nil -> base
      "" -> base
      detail -> "#{base} (#{detail})"
    end
  end

  defp resolve_session_node(session_id) do
    find_running_owner(session_id, :session) ||
      stored_owner_node(ClawCode.SessionStore.owner_node(session_id)) ||
      Cluster.owner_node(:session, session_id)
  end

  defp resolve_workflow_node(workflow_id) do
    find_running_owner(workflow_id, :workflow) ||
      stored_owner_node(ClawCode.WorkflowStore.owner_node(workflow_id)) ||
      Cluster.owner_node(:workflow, workflow_id)
  end

  defp find_running_owner(identifier, :session) do
    find_running_node(identifier, :session_running?)
  end

  defp find_running_owner(identifier, :workflow) do
    find_running_node(identifier, :workflow_running?)
  end

  defp find_running_node(identifier, function) do
    cond do
      apply(__MODULE__, function, [identifier]) ->
        node()

      not Node.alive?() ->
        nil

      true ->
        Enum.find(Node.list(), fn target ->
          case Cluster.rpc_call(target, __MODULE__, function, [identifier]) do
            {:ok, true} -> true
            _ -> false
          end
        end)
    end
  end

  defp session_running?(session_id), do: Registry.lookup(ClawCode.SessionRegistry, session_id) != []
  defp workflow_running?(workflow_id), do: Registry.lookup(ClawCode.WorkflowRegistry, workflow_id) != []

  defp stored_owner_node(nil), do: nil

  defp stored_owner_node(owner_node) do
    parsed = Cluster.parse_owner_node(owner_node)

    if Cluster.reachable_node?(parsed), do: parsed, else: nil
  end

  defp call_node(target, function, args) do
    with {:ok, result} <- Cluster.rpc_call(target, __MODULE__, function, args) do
      result
    end
  end

  defp normalize_start({:ok, pid}), do: {:ok, pid}
  defp normalize_start({:error, {:already_started, pid}}), do: {:ok, pid}
  defp normalize_start(other), do: other
end
