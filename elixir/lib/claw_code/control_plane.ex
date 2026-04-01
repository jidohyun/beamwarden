defmodule ClawCode.ControlPlane do
  @moduledoc false

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
end
