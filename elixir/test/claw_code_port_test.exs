defmodule ClawCodePortTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "manifest counts elixir files" do
    manifest = ClawCode.PortManifest.build()
    assert manifest.total_elixir_files >= 10
    assert manifest.top_level_modules != []
  end

  test "summary mentions workspace" do
    summary = ClawCode.QueryEngine.from_workspace() |> ClawCode.QueryEngine.render_summary()
    assert summary =~ "Elixir Porting Workspace Summary"
    assert summary =~ "Command surface:"
    assert summary =~ "Tool surface:"
  end

  test "cli summary runs" do
    output = capture_io(fn -> assert 0 == ClawCode.CLI.main(["summary"]) end)
    assert output =~ "Elixir Porting Workspace Summary"
  end

  test "parity audit runs" do
    output = capture_io(fn -> assert 0 == ClawCode.CLI.main(["parity-audit"]) end)
    assert output =~ "Parity Audit"
  end

  test "command and tool snapshots are nontrivial" do
    assert length(ClawCode.Commands.ported_commands()) >= 150
    assert length(ClawCode.Tools.ported_tools()) >= 100
  end

  test "commands and tools cli run" do
    commands_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["commands", "--limit", "5", "--query", "review"])
      end)

    tools_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["tools", "--limit", "5", "--query", "MCP"])
      end)

    assert commands_output =~ "Command entries:"
    assert tools_output =~ "Tool entries:"
  end

  test "route and show entry cli run" do
    route_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["route", "review MCP tool", "--limit", "5"])
      end)

    show_command = capture_io(fn -> assert 0 == ClawCode.CLI.main(["show-command", "review"]) end)
    show_tool = capture_io(fn -> assert 0 == ClawCode.CLI.main(["show-tool", "MCPTool"]) end)

    assert String.downcase(route_output) =~ "review"
    assert String.downcase(show_command) =~ "review"
    assert String.downcase(show_tool) =~ "mcptool"
  end

  test "bootstrap cli runs" do
    output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["bootstrap", "review MCP tool", "--limit", "5"])
      end)

    assert output =~ "Runtime Session"
    assert output =~ "Startup Steps"
    assert output =~ "Routed Matches"
  end

  test "bootstrap session tracks turn state" do
    session = ClawCode.Runtime.bootstrap_session("review MCP tool", limit: 5)
    assert length(session.turn_result.matched_tools) >= 1
    assert session.turn_result.output =~ "Prompt:"
    assert session.turn_result.usage.input_tokens >= 1
  end

  test "bootstrap persistence matches turn result usage" do
    session = ClawCode.Runtime.bootstrap_session("review MCP tool", limit: 5)
    session_id = Path.basename(session.persisted_session_path, ".json")
    stored = ClawCode.SessionStore.load_session(session_id)

    assert stored.input_tokens == session.turn_result.usage.input_tokens
    assert stored.output_tokens == session.turn_result.usage.output_tokens
  end

  test "tool permission filtering cli runs" do
    output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["tools", "--limit", "10", "--deny-prefix", "mcp"])
      end)

    assert output =~ "Tool entries:"
    refute output =~ "MCPTool"
  end

  test "tool query path honors permission filtering" do
    output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["tools", "--query", "MCP", "--deny-prefix", "mcp"])
      end)

    refute output =~ "MCPTool"
  end

  test "turn loop cli runs" do
    output =
      capture_io(fn ->
        assert 0 ==
                 ClawCode.CLI.main([
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
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["remote-mode", "workspace"]) end)

    ssh_output = capture_io(fn -> assert 0 == ClawCode.CLI.main(["ssh-mode", "workspace"]) end)

    teleport_output =
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["teleport-mode", "workspace"]) end)

    direct_output =
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["direct-connect-mode", "workspace"]) end)

    deep_link_output =
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["deep-link-mode", "workspace"]) end)

    assert remote_output =~ "mode=remote"
    assert ssh_output =~ "mode=ssh"
    assert teleport_output =~ "mode=teleport"
    assert direct_output =~ "mode=direct-connect"
    assert deep_link_output =~ "mode=deep-link"
  end

  test "flush transcript and load session work" do
    output =
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["flush-transcript", "review MCP tool"]) end)

    [path, flushed_line] = output |> String.trim() |> String.split("\n")
    assert flushed_line =~ "flushed=true"
    session_id = Path.basename(path, ".json")
    loaded = capture_io(fn -> assert 0 == ClawCode.CLI.main(["load-session", session_id]) end)
    assert loaded =~ session_id
    assert loaded =~ "messages"
  end

  test "session control plane persists and reports state" do
    session_id = "demo-session-#{System.unique_integer([:positive])}"

    start_output =
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["session-start", session_id]) end)

    submit_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["session-submit", session_id, "review MCP tool"])
      end)

    status_output =
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["session-status", session_id]) end)

    assert start_output =~ "Session Snapshot"
    assert submit_output =~ "\"turns\":1"
    assert status_output =~ "\"session_id\":\"#{session_id}\""
    assert File.exists?(Path.join(ClawCode.session_root(), "#{session_id}.json"))
  end

  test "workflow control plane tracks steps" do
    workflow_id = "demo-flow-#{System.unique_integer([:positive])}"

    start_output =
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["workflow-start", workflow_id]) end)

    add_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["workflow-add-step", workflow_id, "bootstrap session"])
      end)

    complete_output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["workflow-complete-step", workflow_id, "1"])
      end)

    status_output =
      capture_io(fn -> assert 0 == ClawCode.CLI.main(["workflow-status", workflow_id]) end)

    assert start_output =~ "Workflow Snapshot"
    assert add_output =~ "\"title\":\"bootstrap session\""
    assert complete_output =~ "\"status\":\"completed\""
    assert status_output =~ "\"workflow_id\":\"#{workflow_id}\""
  end

  test "missing python mirror concepts are represented in elixir files" do
    expected =
      ~w(cost_hook cost_tracker dialog_launchers ink interactive_helpers project_onboarding_state query repl_launcher task tasks tool)

    present =
      ClawCode.source_root()
      |> Path.join("*.ex")
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".ex"))

    Enum.each(expected, fn name -> assert name in present end)
  end

  test "command graph and tool pool cli run" do
    command_graph = capture_io(fn -> assert 0 == ClawCode.CLI.main(["command-graph"]) end)
    tool_pool = capture_io(fn -> assert 0 == ClawCode.CLI.main(["tool-pool"]) end)
    assert command_graph =~ "Command Graph"
    assert tool_pool =~ "Tool Pool"
  end

  test "mix claw surfaces non-zero exit code for failures" do
    {_output, status} =
      System.cmd("mix", ["claw", "show-tool", "DefinitelyMissingTool"],
        cd: Path.expand("..", __DIR__)
      )

    assert status == 1
  end
end
