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
    submit_prompt(session_id, prompt)
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
    with {:ok, _pid} <- ensure_workflow(workflow_id),
         snapshot <- ClawCode.WorkflowServer.snapshot(workflow_id) do
      steps =
        Enum.map(snapshot.steps, fn step ->
          if step["id"] == task_id do
            step
            |> Map.put("status", status)
            |> maybe_put_description(detail)
          else
            step
          end
        end)

      path = ClawCode.WorkflowStore.save(%{snapshot | steps: steps})
      {:ok, %{snapshot | steps: steps, persisted_workflow_path: path}}
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
    ["Session Snapshot", "", JSON.encode!(snapshot)]
    |> Enum.join("\n")
  end

  def render_workflow(snapshot) when is_map(snapshot) do
    ["Workflow Snapshot", "", JSON.encode!(snapshot)]
    |> Enum.join("\n")
  end

  defp maybe_put_description(step, nil), do: step
  defp maybe_put_description(step, detail), do: Map.put(step, "description", detail)
end
