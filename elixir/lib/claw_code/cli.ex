defmodule ClawCode.CLI do
  @moduledoc false

  def main(args) do
    Application.ensure_all_started(:claw_code)
    {status, output} = run(args)
    IO.puts(output)

    case status do
      :ok -> 0
      :error -> 1
    end
  end

  def run(["summary"]) do
    {:ok, ClawCode.QueryEngine.from_workspace() |> ClawCode.QueryEngine.render_summary()}
  end

  def run(["manifest"]) do
    {:ok, ClawCode.PortManifest.build() |> ClawCode.PortManifest.to_markdown()}
  end

  def run(["parity-audit"]) do
    {:ok, ClawCode.ParityAudit.run() |> ClawCode.ParityAuditResult.to_markdown()}
  end

  def run(["setup-report"]) do
    {:ok, ClawCode.Setup.run() |> ClawCode.SetupReport.as_markdown()}
  end

  def run(["bootstrap-graph"]) do
    {:ok, ClawCode.BootstrapGraph.build() |> ClawCode.BootstrapGraph.as_markdown()}
  end

  def run(["command-graph"]) do
    {:ok, ClawCode.CommandGraph.as_markdown()}
  end

  def run(["tool-pool"]) do
    {:ok, ClawCode.ToolPool.as_markdown()}
  end

  def run(["session-start", session_id]) do
    with {:ok, _pid} <- ClawCode.ControlPlane.ensure_session(session_id),
         {:ok, snapshot} <- ClawCode.ControlPlane.session_snapshot(session_id) do
      {:ok, render_snapshot("Session", snapshot)}
    else
      {:error, reason} -> {:error, "Failed to start session: #{inspect(reason)}"}
    end
  end

  def run(["session-submit", session_id, prompt]) do
    with {:ok, snapshot} <- ClawCode.ControlPlane.submit_prompt(session_id, prompt) do
      {:ok, render_snapshot("Session", snapshot)}
    else
      {:error, reason} -> {:error, "Failed to submit prompt: #{inspect(reason)}"}
    end
  end

  def run(["session-status", session_id]) do
    case ClawCode.ControlPlane.session_snapshot(session_id) do
      {:ok, session} ->
        {:ok, ClawCode.ControlPlane.render_session(session)}

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, reason} ->
        {:error, "Failed to load session status: #{inspect(reason)}"}
    end
  end

  def run(["control-plane-status"]) do
    {:ok, ClawCode.ControlPlane.status_report()}
  end

  def run(["submit-session", session_id, prompt | rest]) do
    {opts, _, _} = OptionParser.parse(rest, strict: [limit: :integer])

    case ClawCode.ControlPlane.submit_session(session_id, prompt, limit: opts[:limit] || 5) do
      {:ok, response} ->
        {:ok,
         Enum.join(
           [
             response.text,
             "",
             "session_id=#{response.session_id}",
             "stop_reason=#{response.stop_reason}",
             "matched_commands=#{Enum.join(response.matched_commands, ", ")}",
             "matched_tools=#{Enum.join(response.matched_tools, ", ")}"
           ],
           "\n"
         )}

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, reason} ->
        {:error, "Failed to submit session: #{inspect(reason)}"}
    end
  end

  def run(["start-workflow", name | tasks]) do
    workflow_tasks =
      if tasks == [],
        do: ClawCode.Tasks.default_tasks(),
        else: ClawCode.Tasks.from_descriptions(tasks)

    case ClawCode.ControlPlane.start_workflow(name, workflow_tasks) do
      {:ok, workflow} ->
        {:ok, ClawCode.ControlPlane.render_workflow(workflow)}

      {:error, reason} ->
        {:error, "Failed to start workflow: #{inspect(reason)}"}
    end
  end

  def run(["workflow-start", workflow_id]) do
    case ClawCode.ControlPlane.start_workflow(workflow_id, []) do
      {:ok, workflow} ->
        {:ok, ClawCode.ControlPlane.render_workflow(workflow)}

      {:error, reason} ->
        {:error, "Failed to start workflow: #{inspect(reason)}"}
    end
  end

  def run(["workflow-add-step", workflow_id, title]) do
    case ClawCode.ControlPlane.add_workflow_step(workflow_id, title) do
      {:ok, workflow} ->
        {:ok, ClawCode.ControlPlane.render_workflow(workflow)}

      {:error, reason} ->
        {:error, "Failed to add workflow step: #{inspect(reason)}"}
    end
  end

  def run(["workflow-complete-step", workflow_id, step_id]) do
    case ClawCode.ControlPlane.complete_workflow_step(workflow_id, step_id) do
      {:ok, workflow} ->
        {:ok, ClawCode.ControlPlane.render_workflow(workflow)}

      {:error, reason} ->
        {:error, "Failed to complete workflow step: #{inspect(reason)}"}
    end
  end

  def run(["workflow-status", workflow_id]) do
    case ClawCode.ControlPlane.workflow_snapshot(workflow_id) do
      {:ok, workflow} ->
        {:ok, ClawCode.ControlPlane.render_workflow(workflow)}

      {:error, :not_found} ->
        {:error, "Workflow not found: #{workflow_id}"}

      {:error, reason} ->
        {:error, "Failed to load workflow status: #{inspect(reason)}"}
    end
  end

  def run(["advance-task", workflow_id, task_id, status | detail_parts]) do
    detail =
      case Enum.join(detail_parts, " ") do
        "" -> nil
        text -> text
      end

    case ClawCode.ControlPlane.advance_task(workflow_id, task_id, status, detail) do
      {:ok, workflow} ->
        {:ok, ClawCode.ControlPlane.render_workflow(workflow)}

      {:error, :not_found} ->
        {:error, "Workflow not found: #{workflow_id}"}

      {:error, reason} ->
        {:error, "Failed to advance task: #{inspect(reason)}"}
    end
  end

  def run(["commands" | rest]) do
    {opts, _, _} =
      OptionParser.parse(rest,
        strict: [
          limit: :integer,
          query: :string,
          no_plugin_commands: :boolean,
          no_skill_commands: :boolean
        ]
      )

    output =
      if opts[:query] do
        ClawCode.Commands.render_command_index(
          limit: opts[:limit] || 20,
          query: opts[:query],
          include_plugin_commands: !opts[:no_plugin_commands],
          include_skill_commands: !opts[:no_skill_commands]
        )
      else
        commands =
          ClawCode.Commands.get_commands(
            include_plugin_commands: !opts[:no_plugin_commands],
            include_skill_commands: !opts[:no_skill_commands]
          )

        Enum.join(
          ["Command entries: #{length(commands)}", ""] ++
            Enum.map(Enum.take(commands, opts[:limit] || 20), &"- #{&1.name} — #{&1.source_hint}"),
          "\n"
        )
      end

    {:ok, output}
  end

  def run(["tools" | rest]) do
    {opts, _, _} =
      OptionParser.parse(rest,
        strict: [
          limit: :integer,
          query: :string,
          simple_mode: :boolean,
          no_mcp: :boolean,
          deny_tool: :keep,
          deny_prefix: :keep
        ]
      )

    output =
      if opts[:query] do
        deny_names = Keyword.get_values(opts, :deny_tool)
        deny_prefixes = Keyword.get_values(opts, :deny_prefix)

        permission_context =
          ClawCode.ToolPermissionContext.from_iterables(deny_names, deny_prefixes)

        ClawCode.Tools.render_tool_index(
          limit: opts[:limit] || 20,
          query: opts[:query],
          simple_mode: !!opts[:simple_mode],
          include_mcp: !opts[:no_mcp],
          permission_context: permission_context
        )
      else
        deny_names = Keyword.get_values(opts, :deny_tool)
        deny_prefixes = Keyword.get_values(opts, :deny_prefix)

        permission_context =
          ClawCode.ToolPermissionContext.from_iterables(deny_names, deny_prefixes)

        tools =
          ClawCode.Tools.get_tools(
            simple_mode: !!opts[:simple_mode],
            include_mcp: !opts[:no_mcp],
            permission_context: permission_context
          )

        Enum.join(
          ["Tool entries: #{length(tools)}", ""] ++
            Enum.map(Enum.take(tools, opts[:limit] || 20), &"- #{&1.name} — #{&1.source_hint}"),
          "\n"
        )
      end

    {:ok, output}
  end

  def run(["route", prompt | rest]) do
    {opts, _, _} = OptionParser.parse(rest, strict: [limit: :integer])

    output =
      ClawCode.Runtime.route_prompt(prompt, opts[:limit] || 5)
      |> case do
        [] ->
          "No mirrored command/tool matches found."

        matches ->
          matches
          |> Enum.map(&"#{&1.kind}\t#{&1.name}\t#{&1.score}\t#{&1.source_hint}")
          |> Enum.join("\n")
      end

    {:ok, output}
  end

  def run(["bootstrap", prompt | rest]) do
    {opts, _, _} = OptionParser.parse(rest, strict: [limit: :integer])

    {:ok,
     prompt
     |> ClawCode.Runtime.bootstrap_session(limit: opts[:limit] || 5)
     |> ClawCode.RuntimeSession.as_markdown()}
  end

  def run(["turn-loop", prompt | rest]) do
    {opts, _, _} =
      OptionParser.parse(rest,
        strict: [limit: :integer, max_turns: :integer, structured_output: :boolean]
      )

    output =
      prompt
      |> ClawCode.Runtime.run_turn_loop(
        limit: opts[:limit] || 5,
        max_turns: opts[:max_turns] || 3,
        structured_output: !!opts[:structured_output]
      )
      |> Enum.with_index(1)
      |> Enum.map(fn {result, idx} ->
        Enum.join(["## Turn #{idx}", result.output, "stop_reason=#{result.stop_reason}"], "\n")
      end)
      |> Enum.join("\n")

    {:ok, output}
  end

  def run(["flush-transcript", prompt]) do
    {engine, _result} =
      ClawCode.QueryEngine.submit_message(ClawCode.QueryEngine.from_workspace(), prompt)

    {engine, path} = ClawCode.QueryEngine.persist_session(engine)
    {:ok, Enum.join([path, "flushed=#{engine.transcript_store.flushed}"], "\n")}
  end

  def run(["load-session", session_id]) do
    session = ClawCode.SessionStore.load_session(session_id)

    {:ok,
     Enum.join(
       [
         session.session_id,
         "#{length(session.messages || [])} messages",
         "in=#{session.input_tokens} out=#{session.output_tokens}"
       ],
       "\n"
     )}
  end

  def run(["remote-mode", target]) do
    {:ok, ClawCode.RemoteRuntime.run_remote_mode(target) |> ClawCode.RuntimeModeReport.as_text()}
  end

  def run(["ssh-mode", target]) do
    {:ok, ClawCode.RemoteRuntime.run_ssh_mode(target) |> ClawCode.RuntimeModeReport.as_text()}
  end

  def run(["teleport-mode", target]) do
    {:ok,
     ClawCode.RemoteRuntime.run_teleport_mode(target) |> ClawCode.RuntimeModeReport.as_text()}
  end

  def run(["direct-connect-mode", target]) do
    {:ok, ClawCode.DirectModes.run_direct_connect(target) |> ClawCode.DirectModeReport.as_text()}
  end

  def run(["deep-link-mode", target]) do
    {:ok, ClawCode.DirectModes.run_deep_link(target) |> ClawCode.DirectModeReport.as_text()}
  end

  def run(["show-command", name]) do
    case ClawCode.Commands.get_command(name) do
      nil -> {:error, "Command not found: #{name}"}
      module -> {:ok, Enum.join([module.name, module.source_hint, module.responsibility], "\n")}
    end
  end

  def run(["show-tool", name]) do
    case ClawCode.Tools.get_tool(name) do
      nil -> {:error, "Tool not found: #{name}"}
      module -> {:ok, Enum.join([module.name, module.source_hint, module.responsibility], "\n")}
    end
  end

  def run(["exec-command", name, prompt]) do
    result = ClawCode.Commands.execute_command(name, prompt)
    if result.handled, do: {:ok, result.message}, else: {:error, result.message}
  end

  def run(["exec-tool", name, payload]) do
    result = ClawCode.Tools.execute_tool(name, payload)
    if result.handled, do: {:ok, result.message}, else: {:error, result.message}
  end

  def run(_args) do
    {:error, "Unknown command"}
  end

  defp render_snapshot(title, snapshot) do
    [
      "#{title} Snapshot",
      "",
      JSON.encode!(snapshot)
    ]
    |> Enum.join("\n")
  end
end
