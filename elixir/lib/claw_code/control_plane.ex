defmodule ClawCode.ControlPlaneSession do
  @moduledoc false
  defstruct id: nil,
            status: "idle",
            engine: nil,
            last_prompt: nil,
            last_response: nil,
            last_stop_reason: nil,
            persisted_session_path: nil,
            submits: 0,
            cost_tracker: %ClawCode.CostTracker{},
            started_at: nil

  def render(%__MODULE__{} = session) do
    lines = [
      "session_id=#{session.id}",
      "status=#{session.status}",
      "turns=#{length(session.engine.mutable_messages)}",
      "permission_denials=#{length(session.engine.permission_denials)}",
      "usage_in=#{session.engine.total_usage.input_tokens}",
      "usage_out=#{session.engine.total_usage.output_tokens}",
      "submits=#{session.submits}",
      "last_stop_reason=#{session.last_stop_reason || "none"}",
      "persisted_session_path=#{session.persisted_session_path || "none"}",
      "last_prompt=#{session.last_prompt || "none"}",
      "cost_units=#{session.cost_tracker.total_units}"
    ]

    Enum.join(lines, "\n")
  end
end

defmodule ClawCode.WorkflowState do
  @moduledoc false
  defstruct id: nil,
            name: nil,
            status: "pending",
            tasks: [],
            started_at: nil,
            updated_at: nil

  def render(%__MODULE__{} = workflow) do
    header = [
      "workflow_id=#{workflow.id}",
      "name=#{workflow.name}",
      "status=#{workflow.status}",
      "task_count=#{length(workflow.tasks)}"
    ]

    Enum.join(
      header ++ ["tasks:"] ++ Enum.map(workflow.tasks, &ClawCode.PortingTask.as_line/1),
      "\n"
    )
  end
end

defmodule ClawCode.SessionServer do
  @moduledoc false
  use GenServer

  alias ClawCode.{
    ControlPlaneSession,
    CostHook,
    CostTracker,
    QueryEngine,
    QueryRequest,
    QueryResponse,
    Runtime
  }

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  def snapshot(id), do: GenServer.call(via(id), :snapshot)

  def submit(id, prompt, opts \\ []),
    do: GenServer.call(via(id), {:submit, %QueryRequest{prompt: prompt}, opts})

  def stop(id), do: GenServer.stop(via(id), :normal)

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    engine = build_engine(id, opts)
    resumed? = Keyword.get(opts, :resume_from) != nil
    persisted_path = persisted_session_path(id)

    state = %ControlPlaneSession{
      id: id,
      status: if(resumed?, do: "resumed", else: "idle"),
      engine: engine,
      last_stop_reason: if(resumed?, do: "loaded", else: nil),
      persisted_session_path: if(File.exists?(persisted_path), do: persisted_path),
      submits: if(resumed?, do: length(engine.mutable_messages), else: 0),
      cost_tracker: %CostTracker{},
      started_at: DateTime.utc_now()
    }

    case Keyword.get(opts, :prompt) do
      nil -> {:ok, state}
      prompt -> {:ok, elem(process_prompt(state, prompt, opts), 0)}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:submit, %QueryRequest{} = request, opts}, _from, state) do
    {next_state, response} = process_prompt(state, request.prompt, opts)
    {:reply, response, next_state}
  end

  defp build_engine(id, opts) do
    case Keyword.get(opts, :resume_from) do
      nil -> %QueryEngine{QueryEngine.from_workspace() | session_id: id}
      session_id -> QueryEngine.from_saved_session(session_id)
    end
  end

  defp process_prompt(%ControlPlaneSession{} = state, prompt, opts) do
    matches = Runtime.route_prompt(prompt, Keyword.get(opts, :limit, 5))
    command_names = Enum.map(Enum.filter(matches, &(&1.kind == "command")), & &1.name)
    tool_names = Enum.map(Enum.filter(matches, &(&1.kind == "tool")), & &1.name)
    denials = Runtime.permission_denials_for_matches(matches)

    {engine, result} =
      QueryEngine.submit_message(state.engine, prompt, command_names, tool_names, denials)

    {persisted_engine, path} = QueryEngine.persist_session(engine)

    next_state = %ControlPlaneSession{
      state
      | engine: persisted_engine,
        status: session_status(result.stop_reason),
        last_prompt: prompt,
        last_response: result.output,
        last_stop_reason: result.stop_reason,
        persisted_session_path: path,
        submits: state.submits + 1,
        cost_tracker:
          CostHook.apply(
            state.cost_tracker,
            "session_submit",
            result.usage.input_tokens + result.usage.output_tokens
          )
    }

    response = %QueryResponse{
      text: result.output,
      session_id: next_state.id,
      stop_reason: result.stop_reason,
      matched_commands: result.matched_commands,
      matched_tools: result.matched_tools
    }

    {next_state, response}
  end

  defp session_status("completed"), do: "active"
  defp session_status(other), do: other

  defp via(id), do: {:via, Registry, {ClawCode.SessionRegistry, id}}
  defp persisted_session_path(id), do: Path.join(ClawCode.session_root(), "#{id}.json")
end

defmodule ClawCode.WorkflowServer do
  @moduledoc false
  use GenServer

  alias ClawCode.{PortingTask, Tasks, WorkflowState}

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  def snapshot(id), do: GenServer.call(via(id), :snapshot)

  def transition_task(id, task_id, status, detail \\ nil) do
    GenServer.call(via(id), {:transition_task, task_id, status, detail})
  end

  def stop(id), do: GenServer.stop(via(id), :normal)

  @impl true
  def init(opts) do
    state =
      case Keyword.get(opts, :state) do
        %WorkflowState{} = persisted ->
          persisted

        nil ->
          id = Keyword.fetch!(opts, :id)
          tasks = normalize_tasks(Keyword.get(opts, :tasks, Tasks.default_tasks()))
          now = DateTime.utc_now()

          %WorkflowState{
            id: id,
            name: Keyword.get(opts, :name, id),
            tasks: tasks,
            status: workflow_status(tasks),
            started_at: now,
            updated_at: now
          }
      end

    ClawCode.ControlPlane.persist_workflow(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:transition_task, task_id, status, detail}, _from, %WorkflowState{} = state) do
    tasks =
      Enum.map(state.tasks, fn
        %PortingTask{id: ^task_id} = task ->
          %PortingTask{task | status: status, detail: detail}

        %PortingTask{} = task ->
          task

        task ->
          task
      end)

    next_state = %WorkflowState{
      state
      | tasks: tasks,
        status: workflow_status(tasks),
        updated_at: DateTime.utc_now()
    }

    ClawCode.ControlPlane.persist_workflow(next_state)
    {:reply, next_state, next_state}
  end

  defp normalize_tasks(tasks) do
    Enum.map(tasks, fn
      %PortingTask{} = task ->
        task

      description when is_binary(description) ->
        %PortingTask{id: slug(description), description: description}
    end)
  end

  defp workflow_status(tasks) do
    cond do
      Enum.any?(tasks, &(&1.status == "failed")) -> "failed"
      tasks != [] and Enum.all?(tasks, &(&1.status == "completed")) -> "completed"
      Enum.any?(tasks, &(&1.status == "in_progress")) -> "in_progress"
      true -> "pending"
    end
  end

  defp slug(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp via(id), do: {:via, Registry, {ClawCode.WorkflowRegistry, id}}
end

defmodule ClawCode.ControlPlane do
  @moduledoc false

  alias ClawCode.{
    ControlPlaneSession,
    DialogLaunchers,
    InkPanel,
    InteractiveHelpers,
    PortingTask,
    ProjectOnboardingState,
    ToolDefinition,
    WorkflowState
  }

      [] ->
        DynamicSupervisor.start_child(
          ClawCode.SessionSupervisor,
          {ClawCode.SessionServer, session_id}
        )
    end
  end

  def resume_session(session_id) do
    if Registry.lookup(ClawCode.SessionRegistry, session_id) == [] do
      start_session(id: session_id, resume_from: session_id)
    else
      {:ok, ClawCode.SessionServer.snapshot(session_id)}
    end
  end

  def submit_session(session_id, prompt, opts \\ []) do
    with {:ok, _session} <- ensure_session_running(session_id) do
      ClawCode.SessionServer.submit(session_id, prompt, opts)
    end
  end

  def session_snapshot(session_id) do
    with {:ok, _session} <- ensure_session_running(session_id) do
      ClawCode.SessionServer.snapshot(session_id)
    end
  end

  def ensure_session_running(session_id) do
    cond do
      Registry.lookup(ClawCode.SessionRegistry, session_id) != [] ->
        {:ok, ClawCode.SessionServer.snapshot(session_id)}

      File.exists?(Path.join(ClawCode.session_root(), "#{session_id}.json")) ->
        resume_session(session_id)

      true ->
        {:error, :not_found}
    end
  end

  def resume_workflow(workflow_id) do
    if Registry.lookup(ClawCode.WorkflowRegistry, workflow_id) == [] do
      case load_persisted_workflow(workflow_id) do
        nil ->
          {:error, :not_found}

        %WorkflowState{} = workflow ->
          with {:ok, _pid} <-
                 DynamicSupervisor.start_child(
                   ClawCode.WorkflowSupervisor,
                   {ClawCode.WorkflowServer,
                    [id: workflow.id, name: workflow.name, state: workflow]}
                 ) do
            {:ok, ClawCode.WorkflowServer.snapshot(workflow.id)}
          end
      end
    else
      {:ok, ClawCode.WorkflowServer.snapshot(workflow_id)}
    end
  end

  def workflow_snapshot(workflow_id) do
    with {:ok, _workflow} <- ensure_workflow_running(workflow_id) do
      ClawCode.WorkflowServer.snapshot(workflow_id)
    end
  end

  def advance_task(workflow_id, task_id, status, detail \\ nil) do
    with {:ok, _workflow} <- ensure_workflow_running(workflow_id) do
      ClawCode.WorkflowServer.transition_task(workflow_id, task_id, status, detail)
    end
  end

  def ensure_workflow_running(workflow_id) do
    cond do
      Registry.lookup(ClawCode.WorkflowRegistry, workflow_id) != [] ->
        {:ok, ClawCode.WorkflowServer.snapshot(workflow_id)}

      workflow = load_persisted_workflow(workflow_id) ->
        resume_workflow(workflow.id)

      true ->
        {:error, :not_found}
    end
  end

  def persist_workflow(%WorkflowState{} = workflow) do
    directory = workflow_store_root()
    File.mkdir_p!(directory)
    path = Path.join(directory, "#{workflow.id}.json")

    payload = %{
      id: workflow.id,
      name: workflow.name,
      status: workflow.status,
      started_at: encode_datetime(workflow.started_at),
      updated_at: encode_datetime(workflow.updated_at),
      tasks:
        Enum.map(workflow.tasks, fn task ->
          %{id: task.id, description: task.description, status: task.status, detail: task.detail}
        end)
    }

    File.write!(path, JSON.encode!(payload))
    path
  end

  defp load_persisted_workflow(workflow_id) do
    path = Path.join(workflow_store_root(), "#{workflow_id}.json")

    if File.exists?(path) do
      data = path |> File.read!() |> JSON.decode!()

      %WorkflowState{
        id: data["id"],
        name: data["name"],
        status: data["status"],
        started_at: decode_datetime(data["started_at"]),
        updated_at: decode_datetime(data["updated_at"]),
        tasks:
          Enum.map(data["tasks"] || [], fn task ->
            %PortingTask{
              id: task["id"],
              description: task["description"],
              status: task["status"],
              detail: task["detail"]
            }
          end)
      }
    end
  end

  defp workflow_store_root do
    Path.join(ClawCode.session_root(), "workflows")
  end

  defp persisted_session_count do
    ClawCode.session_root()
    |> Path.join("*.json")
    |> Path.wildcard()
    |> length()
  end

  defp persisted_workflow_count do
    workflow_store_root()
    |> Path.join("*.json")
    |> Path.wildcard()
    |> length()
  end

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp decode_datetime(nil), do: nil

  defp decode_datetime(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
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

  def list_sessions do
    list_registry_keys(ClawCode.SessionRegistry)
    |> Enum.map(&ClawCode.SessionServer.snapshot/1)
  end

  def list_workflows do
    list_registry_keys(ClawCode.WorkflowRegistry)
    |> Enum.map(&ClawCode.WorkflowServer.snapshot/1)
  end

  def status_report do
    sessions = list_sessions()
    workflows = list_workflows()
    onboarding = ProjectOnboardingState.current()
    persisted_sessions = persisted_session_count()
    persisted_workflows = persisted_workflow_count()

    body =
      [
        "# OTP Control Plane",
        "",
        "Sessions: #{length(sessions)}",
        "Workflows: #{length(workflows)}",
        "Persisted sessions: #{persisted_sessions}",
        "Persisted workflows: #{persisted_workflows}",
        "Onboarding: #{ProjectOnboardingState.summary(onboarding)}",
        "Dialogs:",
        DialogLaunchers.render(),
        "",
        "Tool definitions:",
        InteractiveHelpers.bulletize(
          Enum.map(ToolDefinition.default_tools(), &"#{&1.name} — #{&1.purpose}")
        )
      ] ++
        render_sessions(sessions) ++ render_workflows(workflows)

    InkPanel.render(Enum.join(body, "\n"))
  end

  def render_session(%ControlPlaneSession{} = session), do: ControlPlaneSession.render(session)
  def render_workflow(%WorkflowState{} = workflow), do: WorkflowState.render(workflow)

  defp render_sessions([]), do: ["", "No supervised sessions"]
  defp render_sessions(sessions), do: ["", "Sessions:"] ++ Enum.map(sessions, &render_session/1)

  defp render_workflows([]), do: ["", "No supervised workflows"]

  defp render_workflows(workflows) do
    ["", "Workflows:"] ++ Enum.map(workflows, &render_workflow/1)
  end

  defp list_registry_keys(registry) do
    case Process.whereis(registry) do
      nil ->
        []

      _pid ->
        Registry.select(registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
        |> Enum.sort()
    end
  end
end
