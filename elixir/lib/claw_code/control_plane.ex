defmodule ClawCode.ControlPlane do
  @moduledoc false

  alias ClawCode.PortingTask

  def ensure_session(session_id) do
    case Registry.lookup(ClawCode.SessionRegistry, session_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          ClawCode.SessionSupervisor,
          {ClawCode.SessionServer, session_id}
        )
    end
  end

  def submit_prompt(session_id, prompt) do
    with {:ok, _pid} <- ensure_session(session_id) do
      {:ok, ClawCode.SessionServer.submit(session_id, prompt)}
    end
  end

  def session_snapshot(session_id) do
    with {:ok, _pid} <- ensure_session(session_id) do
      {:ok, ClawCode.SessionServer.snapshot(session_id)}
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
    case Registry.lookup(ClawCode.WorkflowRegistry, workflow_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          ClawCode.WorkflowSupervisor,
          {ClawCode.WorkflowServer, workflow_id}
        )
    end
  end

  def add_workflow_step(workflow_id, title, description \\ nil) do
    with {:ok, _pid} <- ensure_workflow(workflow_id) do
      {:ok, ClawCode.WorkflowServer.add_step(workflow_id, title, description)}
    end
  end

  def complete_workflow_step(workflow_id, step_id) do
    with {:ok, _pid} <- ensure_workflow(workflow_id) do
      {:ok, ClawCode.WorkflowServer.complete_step(workflow_id, step_id)}
    end
  end

  def workflow_snapshot(workflow_id) do
    with {:ok, _pid} <- ensure_workflow(workflow_id) do
      {:ok, ClawCode.WorkflowServer.snapshot(workflow_id)}
    end
  end

  def start_workflow(workflow_id, tasks \\ []) do
    with {:ok, _pid} <- ensure_workflow(workflow_id) do
      Enum.each(tasks, fn
        %PortingTask{} = task ->
          ClawCode.WorkflowServer.add_step(workflow_id, task.title || task.id, task.description)

        description when is_binary(description) ->
          ClawCode.WorkflowServer.add_step(workflow_id, description)
      end)

      workflow_snapshot(workflow_id)
    end
  end

  def advance_task(workflow_id, task_id, status, detail \\ nil) do
    with {:ok, _pid} <- ensure_workflow(workflow_id) do
      {:ok, ClawCode.WorkflowServer.transition_step(workflow_id, task_id, status, detail)}
    end
  end

  def list_sessions do
    ClawCode.SessionRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(&ClawCode.SessionServer.snapshot/1)
  end

  def list_workflows do
    ClawCode.WorkflowRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(&ClawCode.WorkflowServer.snapshot/1)
  end

  def status_report do
    sessions = list_sessions()
    workflows = list_workflows()

    [
      "# OTP Control Plane",
      "",
      "Sessions: #{length(sessions)}",
      "Workflows: #{length(workflows)}",
      "",
      if(sessions == [],
        do: "No supervised sessions",
        else: Enum.map(sessions, &"session=#{&1.session_id} turns=#{&1.turns}")
      ),
      "",
      if(workflows == [],
        do: "No supervised workflows",
        else: Enum.map(workflows, &"workflow=#{&1.workflow_id} steps=#{length(&1.steps)}")
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
      "task_count=#{length(snapshot.steps)}",
      "tasks:",
      Enum.map(snapshot.steps, &task_line/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

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
end
