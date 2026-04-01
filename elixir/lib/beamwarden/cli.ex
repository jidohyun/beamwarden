defmodule Beamwarden.CLI do
  @moduledoc false

  def main(args) do
    case Beamwarden.Daemon.preflight(args) do
      :ok ->
        :ok

      {:error, reason} ->
        return_status({:error, "Failed to prepare daemon mode: #{inspect(reason)}"})
    end

    Beamwarden.AppIdentity.ensure_started()
    return_status(run(args))
  end

  def run(args) do
    :ok = Beamwarden.Daemon.ensure_runtime(args)

    case Beamwarden.Daemon.maybe_proxy(args) do
      {:proxy, result} -> result
      :local -> run_local(args)
    end
  end

  def run_local(["summary"]) do
    {:ok, Beamwarden.QueryEngine.from_workspace() |> Beamwarden.QueryEngine.render_summary()}
  end

  def run_local(["manifest"]) do
    {:ok, Beamwarden.PortManifest.build() |> Beamwarden.PortManifest.to_markdown()}
  end

  def run_local(["parity-audit"]) do
    {:ok, Beamwarden.ParityAudit.run() |> Beamwarden.ParityAuditResult.to_markdown()}
  end

  def run_local(["setup-report"]) do
    {:ok, Beamwarden.Setup.run() |> Beamwarden.SetupReport.as_markdown()}
  end

  def run_local(["bootstrap-graph"]) do
    {:ok, Beamwarden.BootstrapGraph.build() |> Beamwarden.BootstrapGraph.as_markdown()}
  end

  def run_local(["command-graph"]) do
    {:ok, Beamwarden.CommandGraph.as_markdown()}
  end

  def run_local(["tool-pool"]) do
    {:ok, Beamwarden.ToolPool.as_markdown()}
  end

  def run_local(["daemon-status"]) do
    {:ok, Beamwarden.Daemon.status_report()}
  end

  def run_local(["daemon-run" | rest]) do
    {opts, _, _} = OptionParser.parse(rest, strict: [name: :string, cookie: :string])

    case Beamwarden.Daemon.start_server(opts) do
      {:ok, output} -> {:daemon, output}
      {:error, reason} -> {:error, "Failed to start daemon mode: #{inspect(reason)}"}
    end
  end

  def run_local(["daemon-stop"]) do
    Beamwarden.Daemon.stop_server()
  end

  def run_local(["session-start", session_id]) do
    with {:ok, _pid} <- Beamwarden.ControlPlane.ensure_session(session_id),
         {:ok, snapshot} <- Beamwarden.ControlPlane.session_snapshot(session_id) do
      {:ok, render_snapshot("Session", snapshot)}
    else
      {:error, reason} -> {:error, "Failed to start session: #{inspect(reason)}"}
    end
  end

  def run_local(["start-session", "--id", session_id, prompt]) do
    with {:ok, _pid} <- Beamwarden.ControlPlane.ensure_session(session_id),
         {:ok, _snapshot} <- Beamwarden.ControlPlane.submit_prompt(session_id, prompt),
         {:ok, snapshot} <- Beamwarden.ControlPlane.session_snapshot(session_id) do
      {:ok, Beamwarden.ControlPlane.render_session(snapshot)}
    else
      {:error, reason} -> {:error, "Failed to start session: #{inspect(reason)}"}
    end
  end

  def run_local(["session-submit", session_id, prompt]) do
    with {:ok, snapshot} <- Beamwarden.ControlPlane.submit_prompt(session_id, prompt) do
      {:ok, Beamwarden.ControlPlane.render_session(snapshot)}
    else
      {:error, reason} -> {:error, "Failed to submit prompt: #{inspect(reason)}"}
    end
  end

  def run_local(["session-status", session_id]) do
    case Beamwarden.ControlPlane.session_snapshot(session_id) do
      {:ok, session} -> {:ok, Beamwarden.ControlPlane.render_session(session)}
      {:error, :not_found} -> {:error, "Session not found: #{session_id}"}
      {:error, reason} -> {:error, "Failed to load session status: #{inspect(reason)}"}
    end
  end

  def run_local(["control-plane-status"]) do
    {:ok, Beamwarden.ControlPlane.status_report()}
  end

  def run_local(["cluster-status"]) do
    {:ok, Beamwarden.Cluster.status_report()}
  end

  def run_local(["cluster-connect", target]) do
    case Beamwarden.Cluster.connect(target) do
      {:ok, result} ->
        {:ok, render_cluster_action("Cluster Connect", result)}

      {:error, result} when is_map(result) ->
        {:error, render_cluster_action("Cluster Connect", result)}

      {:error, :local_node_not_distributed} ->
        {:error, "Cluster connect requires a distributed node; start with --sname/--name first"}
    end
  end

  def run_local(["cluster-disconnect", target]) do
    case Beamwarden.Cluster.disconnect(target) do
      {:ok, result} ->
        {:ok, render_cluster_action("Cluster Disconnect", result)}

      {:error, result} when is_map(result) ->
        {:error, render_cluster_action("Cluster Disconnect", result)}

      {:error, :local_node_not_distributed} ->
        {:error,
         "Cluster disconnect requires a distributed node; start with --sname/--name first"}

      {:error, :cannot_disconnect_current_node} ->
        {:error, "Cannot disconnect the current node"}
    end
  end

  def run_local(["submit-session", session_id, prompt | rest]) do
    {opts, _, _} = OptionParser.parse(rest, strict: [limit: :integer])

    case Beamwarden.ControlPlane.submit_session(session_id, prompt, limit: opts[:limit] || 5) do
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
           "
"
         )}

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, reason} ->
        {:error, "Failed to submit session: #{inspect(reason)}"}
    end
  end

  def run_local(["start-workflow", name | tasks]) do
    workflow_tasks =
      if tasks == [],
        do: Beamwarden.Tasks.default_tasks(),
        else: Beamwarden.Tasks.from_descriptions(tasks)

    case Beamwarden.ControlPlane.start_workflow(name, workflow_tasks) do
      {:ok, workflow} -> {:ok, Beamwarden.ControlPlane.render_workflow(workflow)}
      {:error, reason} -> {:error, "Failed to start workflow: #{inspect(reason)}"}
    end
  end

  def run_local(["workflow-start", workflow_id]) do
    case Beamwarden.ControlPlane.start_workflow(workflow_id, []) do
      {:ok, workflow} -> {:ok, Beamwarden.ControlPlane.render_workflow(workflow)}
      {:error, reason} -> {:error, "Failed to start workflow: #{inspect(reason)}"}
    end
  end

  def run_local(["workflow-add-step", workflow_id, title]) do
    case Beamwarden.ControlPlane.add_workflow_step(workflow_id, title) do
      {:ok, workflow} -> {:ok, Beamwarden.ControlPlane.render_workflow(workflow)}
      {:error, reason} -> {:error, "Failed to add workflow step: #{inspect(reason)}"}
    end
  end

  def run_local(["workflow-complete-step", workflow_id, step_id]) do
    case Beamwarden.ControlPlane.complete_workflow_step(workflow_id, step_id) do
      {:ok, workflow} -> {:ok, Beamwarden.ControlPlane.render_workflow(workflow)}
      {:error, reason} -> {:error, "Failed to complete workflow step: #{inspect(reason)}"}
    end
  end

  def run_local(["dialogs"]) do
    {:ok, Beamwarden.DialogLaunchers.render()}
  end

  def run_local(["repl-banner"]) do
    {:ok, Beamwarden.ReplLauncher.build_banner()}
  end

  def run_local(["default-tasks"]) do
    {:ok,
     Beamwarden.Tasks.default_tasks()
     |> Enum.map(&Beamwarden.PortingTask.as_line/1)
     |> Enum.join("
")}
  end

  def run_local(["tool-definitions"]) do
    {:ok,
     Beamwarden.ToolDefinition.default_tools()
     |> Beamwarden.ToolDefinition.as_lines()
     |> Enum.join("
")}
  end

  def run_local(["query-route", prompt | rest]) do
    {opts, _, _} = OptionParser.parse(rest, strict: [limit: :integer])
    limit = opts[:limit] || 5
    matches = Beamwarden.Runtime.route_prompt(prompt, limit)

    {:ok,
     [
       "# Query Engine Route",
       "",
       "Prompt: #{prompt}",
       "Matches:",
       Enum.map(matches, &"- [#{&1.kind}] #{&1.name} (#{&1.score}) — #{&1.source_hint}")
     ]
     |> List.flatten()
     |> Enum.join("
")}
  end

  def run_local(["workflow-status", workflow_id]) do
    case Beamwarden.ControlPlane.workflow_snapshot(workflow_id) do
      {:ok, workflow} -> {:ok, Beamwarden.ControlPlane.render_workflow(workflow)}
      {:error, :not_found} -> {:error, "Workflow not found: #{workflow_id}"}
      {:error, reason} -> {:error, "Failed to load workflow status: #{inspect(reason)}"}
    end
  end

  def run_local(["advance-task", workflow_id, task_id, status | detail_parts]) do
    detail =
      case Enum.join(detail_parts, " ") do
        "" -> nil
        text -> text
      end

    case Beamwarden.ControlPlane.advance_task(workflow_id, task_id, status, detail) do
      {:ok, workflow} -> {:ok, Beamwarden.ControlPlane.render_workflow(workflow)}
      {:error, :not_found} -> {:error, "Workflow not found: #{workflow_id}"}
      {:error, reason} -> {:error, "Failed to advance task: #{inspect(reason)}"}
    end
  end

  def run_local(["commands" | rest]) do
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
        Beamwarden.Commands.render_command_index(
          limit: opts[:limit] || 20,
          query: opts[:query],
          include_plugin_commands: !opts[:no_plugin_commands],
          include_skill_commands: !opts[:no_skill_commands]
        )
      else
        commands =
          Beamwarden.Commands.get_commands(
            include_plugin_commands: !opts[:no_plugin_commands],
            include_skill_commands: !opts[:no_skill_commands]
          )

        Enum.join(
          ["Command entries: #{length(commands)}", ""] ++
            Enum.map(Enum.take(commands, opts[:limit] || 20), &"- #{&1.name} — #{&1.source_hint}"),
          "
"
        )
      end

    {:ok, output}
  end

  def run_local(["tools" | rest]) do
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
          Beamwarden.ToolPermissionContext.from_iterables(deny_names, deny_prefixes)

        Beamwarden.Tools.render_tool_index(
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
          Beamwarden.ToolPermissionContext.from_iterables(deny_names, deny_prefixes)

        tools =
          Beamwarden.Tools.get_tools(
            simple_mode: !!opts[:simple_mode],
            include_mcp: !opts[:no_mcp],
            permission_context: permission_context
          )

        Enum.join(
          ["Tool entries: #{length(tools)}", ""] ++
            Enum.map(Enum.take(tools, opts[:limit] || 20), &"- #{&1.name} — #{&1.source_hint}"),
          "
"
        )
      end

    {:ok, output}
  end

  def run_local(["route", prompt | rest]) do
    {opts, _, _} = OptionParser.parse(rest, strict: [limit: :integer])

    output =
      Beamwarden.Runtime.route_prompt(prompt, opts[:limit] || 5)
      |> case do
        [] ->
          "No mirrored command/tool matches found."

        matches ->
          matches
          |> Enum.map(&"#{&1.kind}	#{&1.name}	#{&1.score}	#{&1.source_hint}")
          |> Enum.join("
")
      end

    {:ok, output}
  end

  def run_local(["bootstrap", prompt | rest]) do
    {opts, _, _} = OptionParser.parse(rest, strict: [limit: :integer])

    {:ok,
     prompt
     |> Beamwarden.Runtime.bootstrap_session(limit: opts[:limit] || 5)
     |> Beamwarden.RuntimeSession.as_markdown()}
  end

  def run_local(["turn-loop", prompt | rest]) do
    {opts, _, _} =
      OptionParser.parse(rest,
        strict: [limit: :integer, max_turns: :integer, structured_output: :boolean]
      )

    output =
      prompt
      |> Beamwarden.Runtime.run_turn_loop(
        limit: opts[:limit] || 5,
        max_turns: opts[:max_turns] || 3,
        structured_output: !!opts[:structured_output]
      )
      |> Enum.with_index(1)
      |> Enum.map(fn {result, idx} ->
        Enum.join(["## Turn #{idx}", result.output, "stop_reason=#{result.stop_reason}"], "
")
      end)
      |> Enum.join("
")

    {:ok, output}
  end

  def run_local(["flush-transcript", prompt]) do
    {engine, _result} =
      Beamwarden.QueryEngine.submit_message(Beamwarden.QueryEngine.from_workspace(), prompt)

    {engine, path} = Beamwarden.QueryEngine.persist_session(engine)
    {:ok, Enum.join([path, "flushed=#{engine.transcript_store.flushed}"], "
")}
  end

  def run_local(["load-session", session_id]) do
    session = Beamwarden.SessionStore.load_session(session_id)

    {:ok,
     Enum.join(
       [
         session.session_id,
         "#{length(session.messages || [])} messages",
         "in=#{session.input_tokens} out=#{session.output_tokens}"
       ],
       "
"
     )}
  end

  def run_local(["remote-mode", target]) do
    {:ok,
     Beamwarden.RemoteRuntime.run_remote_mode(target) |> Beamwarden.RuntimeModeReport.as_text()}
  end

  def run_local(["ssh-mode", target]) do
    {:ok, Beamwarden.RemoteRuntime.run_ssh_mode(target) |> Beamwarden.RuntimeModeReport.as_text()}
  end

  def run_local(["teleport-mode", target]) do
    {:ok,
     Beamwarden.RemoteRuntime.run_teleport_mode(target) |> Beamwarden.RuntimeModeReport.as_text()}
  end

  def run_local(["direct-connect-mode", target]) do
    {:ok,
     Beamwarden.DirectModes.run_direct_connect(target) |> Beamwarden.DirectModeReport.as_text()}
  end

  def run_local(["deep-link-mode", target]) do
    {:ok, Beamwarden.DirectModes.run_deep_link(target) |> Beamwarden.DirectModeReport.as_text()}
  end

  def run_local(["show-command", name]) do
    case Beamwarden.Commands.get_command(name) do
      nil -> {:error, "Command not found: #{name}"}
      module -> {:ok, Enum.join([module.name, module.source_hint, module.responsibility], "
")}
    end
  end

  def run_local(["show-tool", name]) do
    case Beamwarden.Tools.get_tool(name) do
      nil -> {:error, "Tool not found: #{name}"}
      module -> {:ok, Enum.join([module.name, module.source_hint, module.responsibility], "
")}
    end
  end

  def run_local(["exec-command", name, prompt]) do
    result = Beamwarden.Commands.execute_command(name, prompt)
    if result.handled, do: {:ok, result.message}, else: {:error, result.message}
  end

  def run_local(["exec-tool", name, payload]) do
    result = Beamwarden.Tools.execute_tool(name, payload)
    if result.handled, do: {:ok, result.message}, else: {:error, result.message}
  end

  def run_local(_args) do
    {:error, "Unknown command"}
  end

  defp return_status({:ok, output}) do
    IO.puts(output)
    0
  end

  defp return_status({:error, output}) do
    IO.puts(output)
    1
  end

  defp return_status({:daemon, output}) do
    IO.puts(output)
    Beamwarden.Daemon.block_forever()
    0
  end

  defp render_snapshot(title, snapshot) do
    [title <> " Snapshot", "", JSON.encode!(snapshot)]
    |> Enum.join("
")
  end

  defp render_cluster_action(title, result) do
    [
      title,
      "",
      "node=#{result.node}",
      "connected=#{result.connected}",
      "detail=#{result.detail}",
      "connected_nodes=#{Enum.join(result.connected_nodes, ",")}"
    ]
    |> Enum.join("
")
  end
end
