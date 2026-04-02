defmodule BeamwardenPortTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "manifest counts elixir files" do
    manifest = Beamwarden.PortManifest.build()
    assert manifest.total_elixir_files >= 10
    assert manifest.top_level_modules != []
  end

  test "summary mentions workspace" do
    summary = Beamwarden.QueryEngine.from_workspace() |> Beamwarden.QueryEngine.render_summary()
    assert summary =~ "Elixir Porting Workspace Summary"
    assert summary =~ "Command surface:"
    assert summary =~ "Tool surface:"
  end

  test "cli summary runs" do
    output = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["summary"]) end)
    assert output =~ "Elixir Porting Workspace Summary"
  end

  test "mix beamwarden alias runs the same summary surface" do
    Mix.Task.reenable("beamwarden")

    output =
      capture_io(fn ->
        Mix.Tasks.Beamwarden.run(["summary"])
      end)

    assert output =~ "Elixir Porting Workspace Summary"
  end

  test "repl launcher messaging points users at beamwarden commands" do
    assert Beamwarden.ReplLauncher.launch_message() =~ "mix beamwarden summary"
    assert Beamwarden.ReplLauncher.build_banner() =~ "mix beamwarden summary"
  end

  test "app identity helper keeps beamwarden as the live runtime app" do
    assert Beamwarden.AppIdentity.runtime_app() == :beamwarden
    assert :ok = Beamwarden.AppIdentity.ensure_runtime_started()
  end

  test "parity audit runs" do
    output = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["parity-audit"]) end)
    assert output =~ "Parity Audit"
  end

  test "command and tool snapshots are nontrivial" do
    assert length(Beamwarden.Commands.ported_commands()) >= 150
    assert length(Beamwarden.Tools.ported_tools()) >= 100
  end

  test "elixir workspace owns copied reference snapshots" do
    assert Path.expand(Beamwarden.reference_data_root()) ==
             Path.expand(Path.join(Beamwarden.project_root(), "priv/reference_data"))

    assert File.exists?(Path.join(Beamwarden.reference_data_root(), "commands_snapshot.json"))
    assert File.exists?(Path.join(Beamwarden.reference_data_root(), "tools_snapshot.json"))
    assert length(Beamwarden.ReferenceData.subsystem_snapshots()) >= 10
    refute String.contains?(Beamwarden.reference_data_root(), "reference/python")
  end

  test "commands and tools cli run" do
    commands_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["commands", "--limit", "5", "--query", "review"])
      end)

    tools_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["tools", "--limit", "5", "--query", "MCP"])
      end)

    assert commands_output =~ "Command entries:"
    assert tools_output =~ "Tool entries:"
  end

  test "route and show entry cli run" do
    route_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["route", "review MCP tool", "--limit", "5"])
      end)

    show_command =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["show-command", "review"]) end)

    show_tool = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["show-tool", "MCPTool"]) end)

    assert String.downcase(route_output) =~ "review"
    assert String.downcase(show_command) =~ "review"
    assert String.downcase(show_tool) =~ "mcptool"
  end

  test "bootstrap cli runs" do
    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["bootstrap", "review MCP tool", "--limit", "5"])
      end)

    assert output =~ "Runtime Session"
    assert output =~ "Startup Steps"
    assert output =~ "Routed Matches"
  end

  test "bootstrap session tracks turn state" do
    session = Beamwarden.Runtime.bootstrap_session("review MCP tool", limit: 5)
    assert length(session.turn_result.matched_tools) >= 1
    assert session.turn_result.output =~ "Prompt:"
    assert session.turn_result.usage.input_tokens >= 1
  end

  test "bootstrap persistence matches turn result usage" do
    session = Beamwarden.Runtime.bootstrap_session("review MCP tool", limit: 5)
    session_id = Path.basename(session.persisted_session_path, ".json")
    stored = Beamwarden.SessionStore.load_session(session_id)

    assert stored.input_tokens == session.turn_result.usage.input_tokens
    assert stored.output_tokens == session.turn_result.usage.output_tokens
  end

  test "tool permission filtering cli runs" do
    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["tools", "--limit", "10", "--deny-prefix", "mcp"])
      end)

    assert output =~ "Tool entries:"
    refute output =~ "MCPTool"
  end

  test "tool query path honors permission filtering" do
    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["tools", "--query", "MCP", "--deny-prefix", "mcp"])
      end)

    refute output =~ "MCPTool"
  end

  test "turn loop cli runs" do
    output =
      capture_io(fn ->
        assert 0 ==
                 Beamwarden.CLI.main([
                   "turn-loop",
                   "review MCP tool",
                   "--max-turns",
                   "2",
                   "--structured-output"
                 ])
      end)

    assert output =~ "## Turn 1"
    assert output =~ "stop_reason="
  end

  test "remote and direct mode clis run" do
    remote_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["remote-mode", "workspace"]) end)

    ssh_output = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["ssh-mode", "workspace"]) end)

    teleport_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["teleport-mode", "workspace"]) end)

    direct_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["direct-connect-mode", "workspace"]) end)

    deep_link_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["deep-link-mode", "workspace"]) end)

    assert remote_output =~ "mode=remote"
    assert ssh_output =~ "mode=ssh"
    assert teleport_output =~ "mode=teleport"
    assert direct_output =~ "mode=direct-connect"
    assert deep_link_output =~ "mode=deep-link"
  end

  test "flush transcript and load session work" do
    output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["flush-transcript", "review MCP tool"])
      end)

    [path, flushed_line] = output |> String.trim() |> String.split("\n")
    assert flushed_line =~ "flushed=true"
    session_id = Path.basename(path, ".json")
    loaded = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["load-session", session_id]) end)
    assert loaded =~ session_id
    assert loaded =~ "messages"
  end

  test "session control plane persists and reports state" do
    session_id = "demo-session-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    start_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["session-start", session_id]) end)

    submit_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["session-submit", session_id, "review MCP tool"])
      end)

    status_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["session-status", session_id]) end)

    assert start_output =~ "Session Snapshot"
    assert submit_output =~ "turns=1"
    assert status_output =~ "session_id=#{session_id}"
    assert File.exists?(Path.join(Beamwarden.session_root(), "#{session_id}.json"))
  end

  test "workflow control plane tracks steps" do
    workflow_id = "demo-flow-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    start_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["workflow-start", workflow_id]) end)

    add_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["workflow-add-step", workflow_id, "bootstrap session"])
      end)

    complete_output =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["workflow-complete-step", workflow_id, "1"])
      end)

    status_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["workflow-status", workflow_id]) end)

    assert start_output =~ "Workflow Snapshot"
    assert add_output =~ "bootstrap session"
    assert complete_output =~ "[completed] 1 — bootstrap session"
    assert status_output =~ "workflow_id=#{workflow_id}"
  end

  test "missing python mirror concepts are represented in elixir files" do
    expected =
      ~w(cost_hook cost_tracker dialog_launchers ink interactive_helpers project_onboarding_state query repl_launcher task tasks tool)

    present =
      Beamwarden.source_root()
      |> Path.join("*.ex")
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".ex"))

    Enum.each(expected, fn name -> assert name in present end)
  end

  test "command graph and tool pool cli run" do
    command_graph = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["command-graph"]) end)
    tool_pool = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["tool-pool"]) end)
    assert command_graph =~ "Command Graph"
    assert tool_pool =~ "Tool Pool"
  end

  test "companion cli commands surface the Elixir-first mirror helpers" do
    dialogs = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["dialogs"]) end)
    repl_banner = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["repl-banner"]) end)
    default_tasks = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["default-tasks"]) end)
    tool_defs = capture_io(fn -> assert 0 == Beamwarden.CLI.main(["tool-definitions"]) end)

    query_route =
      capture_io(fn ->
        assert 0 == Beamwarden.CLI.main(["query-route", "review MCP tool", "--limit", "5"])
      end)

    assert dialogs =~ "control_plane"
    assert repl_banner =~ "workflow-oriented"
    assert default_tasks =~ "root-module-parity"
    assert tool_defs =~ "control_plane"
    assert query_route =~ "# Query Engine Route"
    assert query_route =~ "Matches:"
  end

  test "control plane session lifecycle is exposed via the beamwarden cli" do
    session_id = "session-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    on_exit(fn -> maybe_stop_session(session_id) end)

    start_output =
      capture_io(fn ->
        assert 0 ==
                 Beamwarden.CLI.main([
                   "start-session",
                   "--id",
                   session_id,
                   "review MCP tool"
                 ])
      end)

    submit_output =
      capture_io(fn ->
        assert 0 ==
                 Beamwarden.CLI.main([
                   "submit-session",
                   session_id,
                   "review MCP tool",
                   "--limit",
                   "5"
                 ])
      end)

    status_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["session-status", session_id]) end)

    control_plane =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["control-plane-status"]) end)

    assert start_output =~ "session_id=#{session_id}"
    assert start_output =~ "persisted_session_path="
    assert submit_output =~ "stop_reason=completed"
    assert status_output =~ "submits=2"
    assert control_plane =~ "Sessions:"
    assert control_plane =~ session_id
  end

  test "workflow lifecycle is exposed via the beamwarden cli" do
    workflow_name = "port-docs-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    start_output =
      capture_io(fn ->
        assert 0 ==
                 Beamwarden.CLI.main([
                   "start-workflow",
                   workflow_name,
                   "Update README",
                   "Update docs"
                 ])
      end)

    workflow_id =
      start_output
      |> String.split("\n", trim: true)
      |> Enum.find(&String.starts_with?(&1, "workflow_id="))
      |> String.replace_prefix("workflow_id=", "")

    on_exit(fn -> maybe_stop_workflow(workflow_id) end)

    advance_output =
      capture_io(fn ->
        assert 0 ==
                 Beamwarden.CLI.main([
                   "advance-task",
                   workflow_id,
                   "1",
                   "completed",
                   "README refreshed"
                 ])
      end)

    status_output =
      capture_io(fn -> assert 0 == Beamwarden.CLI.main(["workflow-status", workflow_id]) end)

    assert start_output =~ "name=#{workflow_name}"
    assert start_output =~ "Update README"
    assert advance_output =~ "README refreshed"
    assert status_output =~ "workflow_id=#{workflow_id}"
    assert status_output =~ "[completed] 1"
  end

  test "mix beamwarden surfaces non-zero exit code for failures" do
    {_output, status} =
      System.cmd("mix", ["beamwarden", "show-tool", "DefinitelyMissingTool"],
        cd: Path.expand("..", __DIR__)
      )

    assert status == 1
  end

  defp maybe_stop_session(session_id) do
    if Registry.lookup(Beamwarden.SessionRegistry, session_id) != [] do
      Beamwarden.SessionServer.stop(session_id)
    end

    File.rm(Path.join(Beamwarden.session_root(), "#{session_id}.json"))
  end

  defp maybe_stop_workflow(workflow_id) do
    if Registry.lookup(Beamwarden.WorkflowRegistry, workflow_id) != [] do
      Beamwarden.WorkflowServer.stop(workflow_id)
    end

    File.rm(Beamwarden.workflow_path(workflow_id))
  end
end
