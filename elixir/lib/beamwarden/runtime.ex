defmodule Beamwarden.RoutedMatch do
  @moduledoc false
  defstruct [:kind, :name, :source_hint, :score]
end

defmodule Beamwarden.RuntimeSession do
  @moduledoc false
  defstruct prompt: nil,
            context: nil,
            setup: nil,
            setup_report: nil,
            system_init_message: nil,
            history: nil,
            routed_matches: [],
            turn_result: nil,
            command_execution_messages: [],
            tool_execution_messages: [],
            stream_events: [],
            persisted_session_path: nil

  def as_markdown(%__MODULE__{} = session) do
    [
      "# Runtime Session",
      "",
      "Prompt: #{session.prompt}",
      "",
      "## Context",
      Beamwarden.Context.render(session.context),
      "",
      "## Setup",
      "- Elixir: #{session.setup.elixir_version}",
      "- OTP: #{session.setup.otp_release}",
      "- Test command: #{session.setup.test_command}",
      "",
      "## Startup Steps",
      Enum.map(Beamwarden.WorkspaceSetup.startup_steps(), &"- #{&1}"),
      "",
      "## System Init",
      session.system_init_message,
      "",
      "## Routed Matches",
      if(session.routed_matches == [],
        do: ["- none"],
        else:
          Enum.map(
            session.routed_matches,
            &"- [#{&1.kind}] #{&1.name} (#{&1.score}) — #{&1.source_hint}"
          )
      ),
      "",
      "## Command Execution",
      if(session.command_execution_messages == [],
        do: ["none"],
        else: session.command_execution_messages
      ),
      "",
      "## Tool Execution",
      if(session.tool_execution_messages == [],
        do: ["none"],
        else: session.tool_execution_messages
      ),
      "",
      "## Stream Events",
      Enum.map(session.stream_events, &"- #{&1.type}: #{inspect(&1)}"),
      "",
      "## Turn Result",
      session.turn_result.output,
      "",
      "Persisted session path: #{session.persisted_session_path}",
      "",
      Beamwarden.HistoryLog.as_markdown(session.history)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end
end

defmodule Beamwarden.Runtime do
  @moduledoc false

  alias Beamwarden.{
    HistoryLog,
    PermissionDenial,
    QueryEngine,
    QueryEngineConfig,
    RoutedMatch,
    RuntimeSession
  }

  def route_prompt(prompt, limit \\ 5) do
    tokens =
      prompt
      |> String.replace("/", " ")
      |> String.replace("-", " ")
      |> String.split()
      |> Enum.map(&String.downcase/1)
      |> MapSet.new()

    by_kind = %{
      "command" => collect_matches(tokens, Beamwarden.Commands.ported_commands(), "command"),
      "tool" => collect_matches(tokens, Beamwarden.Tools.ported_tools(), "tool")
    }

    selected =
      ["command", "tool"]
      |> Enum.reduce([], fn kind, acc ->
        case Map.get(by_kind, kind, []) do
          [first | _rest] -> acc ++ [first]
          [] -> acc
        end
      end)

    leftovers =
      by_kind
      |> Map.values()
      |> List.flatten()
      |> Enum.reject(fn match ->
        Enum.any?(selected, &(&1.kind == match.kind and &1.name == match.name))
      end)
      |> Enum.sort_by(&{-&1.score, &1.kind, &1.name})

    Enum.take(selected ++ leftovers, limit)
  end

  def bootstrap_session(prompt, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    context = Beamwarden.Context.build()
    setup_report = Beamwarden.Setup.run()
    history = %HistoryLog{}
    engine = QueryEngine.from_workspace()

    history =
      HistoryLog.add(
        history,
        "context",
        "elixir_files=#{context.elixir_file_count}, archive_available=#{context.archive_available}"
      )

    history =
      HistoryLog.add(
        history,
        "registry",
        "commands=#{length(Beamwarden.Commands.ported_commands())}, tools=#{length(Beamwarden.Tools.ported_tools())}"
      )

    matches = route_prompt(prompt, limit)

    command_messages =
      Enum.map(Enum.filter(matches, &(&1.kind == "command")), fn match ->
        Beamwarden.Commands.execute_command(match.name, prompt).message
      end)

    tool_messages =
      Enum.map(Enum.filter(matches, &(&1.kind == "tool")), fn match ->
        Beamwarden.Tools.execute_tool(match.name, prompt).message
      end)

    denials = permission_denials_for_matches(matches)

    {engine, result} =
      QueryEngine.submit_message(
        engine,
        prompt,
        Enum.map(Enum.filter(matches, &(&1.kind == "command")), & &1.name),
        Enum.map(Enum.filter(matches, &(&1.kind == "tool")), & &1.name),
        denials
      )

    stream_events = QueryEngine.events_for_result(engine.session_id, prompt, result)
    {_persisted_engine, persisted_session_path} = QueryEngine.persist_session(engine)

    history =
      history
      |> HistoryLog.add("routing", "matches=#{length(matches)} for prompt=#{inspect(prompt)}")
      |> HistoryLog.add(
        "execution",
        "command_execs=#{length(command_messages)} tool_execs=#{length(tool_messages)}"
      )
      |> HistoryLog.add(
        "turn",
        "commands=#{length(result.matched_commands)} tools=#{length(result.matched_tools)} denials=#{length(result.permission_denials)} stop=#{result.stop_reason}"
      )
      |> HistoryLog.add("session_store", persisted_session_path)

    %RuntimeSession{
      prompt: prompt,
      context: context,
      setup: setup_report.setup,
      setup_report: setup_report,
      system_init_message: Beamwarden.SystemInit.build(true),
      history: history,
      routed_matches: matches,
      turn_result: result,
      command_execution_messages: command_messages,
      tool_execution_messages: tool_messages,
      stream_events: stream_events,
      persisted_session_path: persisted_session_path
    }
  end

  def run_turn_loop(prompt, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    max_turns = Keyword.get(opts, :max_turns, 3)
    structured_output = Keyword.get(opts, :structured_output, false)
    matches = route_prompt(prompt, limit)
    command_names = Enum.map(Enum.filter(matches, &(&1.kind == "command")), & &1.name)
    tool_names = Enum.map(Enum.filter(matches, &(&1.kind == "tool")), & &1.name)

    engine = %QueryEngine{
      QueryEngine.from_workspace()
      | config: %QueryEngineConfig{max_turns: max_turns, structured_output: structured_output}
    }

    Enum.reduce_while(0..(max_turns - 1), {engine, []}, fn turn, {acc_engine, results} ->
      turn_prompt = if turn == 0, do: prompt, else: "#{prompt} [turn #{turn + 1}]"

      {next_engine, result} =
        QueryEngine.submit_message(acc_engine, turn_prompt, command_names, tool_names, [])

      updated = results ++ [result]

      if result.stop_reason == "completed" do
        {:cont, {next_engine, updated}}
      else
        {:halt, {next_engine, updated}}
      end
    end)
    |> elem(1)
  end

  def permission_denials_for_matches(matches) do
    Enum.reduce(matches, [], fn match, acc ->
      if match.kind == "tool" and String.contains?(String.downcase(match.name), "bash") do
        acc ++
          [
            %PermissionDenial{
              tool_name: match.name,
              reason: "destructive shell execution remains gated in the Elixir port"
            }
          ]
      else
        acc
      end
    end)
  end

  defp collect_matches(tokens, modules, kind) do
    modules
    |> Enum.map(fn module ->
      score = score(tokens, module)

      if score > 0,
        do: %RoutedMatch{
          kind: kind,
          name: module.name,
          source_hint: module.source_hint,
          score: score
        }
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{-&1.score, &1.name})
  end

  defp score(tokens, module) do
    haystacks = [
      String.downcase(module.name),
      String.downcase(module.source_hint),
      String.downcase(module.responsibility)
    ]

    tokens
    |> Enum.count(fn token -> Enum.any?(haystacks, &String.contains?(&1, token)) end)
  end
end
