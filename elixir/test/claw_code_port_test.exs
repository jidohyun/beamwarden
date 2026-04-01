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

  test "tool permission filtering cli runs" do
    output =
      capture_io(fn ->
        assert 0 == ClawCode.CLI.main(["tools", "--limit", "10", "--deny-prefix", "mcp"])
      end)

    assert output =~ "Tool entries:"
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

  test "command graph and tool pool cli run" do
    command_graph = capture_io(fn -> assert 0 == ClawCode.CLI.main(["command-graph"]) end)
    tool_pool = capture_io(fn -> assert 0 == ClawCode.CLI.main(["tool-pool"]) end)
    assert command_graph =~ "Command Graph"
    assert tool_pool =~ "Tool Pool"
  end
end
