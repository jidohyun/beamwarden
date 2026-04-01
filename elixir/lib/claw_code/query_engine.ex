defmodule ClawCode.QueryEngineConfig do
  @moduledoc false
  defstruct max_turns: 8,
            max_budget_tokens: 2000,
            compact_after_turns: 12,
            structured_output: false
end

defmodule ClawCode.TurnResult do
  @moduledoc false
  defstruct prompt: nil,
            output: nil,
            matched_commands: [],
            matched_tools: [],
            permission_denials: [],
            usage: %ClawCode.UsageSummary{},
            stop_reason: "completed"
end

defmodule ClawCode.QueryEngine do
  @moduledoc false

  alias ClawCode.{
    PortingBacklog,
    QueryEngineConfig,
    StoredSession,
    TranscriptStore,
    TurnResult,
    UsageSummary
  }

  defstruct manifest: nil,
            config: %QueryEngineConfig{},
            session_id: nil,
            mutable_messages: [],
            permission_denials: [],
            total_usage: %UsageSummary{},
            transcript_store: %TranscriptStore{}

  def from_workspace do
    %__MODULE__{manifest: ClawCode.PortManifest.build(), session_id: unique_id()}
  end

  def from_saved_session(session_id) do
    stored = ClawCode.SessionStore.load_session(session_id)

    %__MODULE__{
      manifest: ClawCode.PortManifest.build(),
      session_id: stored.session_id,
      mutable_messages: stored.messages || [],
      total_usage: %UsageSummary{
        input_tokens: stored.input_tokens,
        output_tokens: stored.output_tokens
      },
      transcript_store: %TranscriptStore{entries: stored.messages || [], flushed: true}
    }
  end

  def submit_message(
        %__MODULE__{} = engine,
        prompt,
        matched_commands \\ [],
        matched_tools \\ [],
        denied_tools \\ []
      ) do
    if length(engine.mutable_messages) >= engine.config.max_turns do
      result = %TurnResult{
        prompt: prompt,
        output: "Max turns reached before processing prompt: #{prompt}",
        matched_commands: matched_commands,
        matched_tools: matched_tools,
        permission_denials: denied_tools,
        usage: engine.total_usage,
        stop_reason: "max_turns_reached"
      }

      {engine, result}
    else
      summary_lines = [
        "Prompt: #{prompt}",
        "Matched commands: #{format_matches(matched_commands)}",
        "Matched tools: #{format_matches(matched_tools)}",
        "Permission denials: #{length(denied_tools)}"
      ]

      output = format_output(summary_lines, engine.config.structured_output, engine.session_id)
      projected_usage = UsageSummary.add_turn(engine.total_usage, prompt, output)

      stop_reason =
        if projected_usage.input_tokens + projected_usage.output_tokens >
             engine.config.max_budget_tokens,
           do: "max_budget_reached",
           else: "completed"

      transcript_store =
        engine.transcript_store
        |> TranscriptStore.append(prompt)
        |> TranscriptStore.compact(engine.config.compact_after_turns)

      updated_engine = %{
        engine
        | mutable_messages:
            compact_messages(
              engine.mutable_messages ++ [prompt],
              engine.config.compact_after_turns
            ),
          permission_denials: engine.permission_denials ++ denied_tools,
          total_usage: projected_usage,
          transcript_store: transcript_store
      }

      result = %TurnResult{
        prompt: prompt,
        output: output,
        matched_commands: matched_commands,
        matched_tools: matched_tools,
        permission_denials: denied_tools,
        usage: projected_usage,
        stop_reason: stop_reason
      }

      {updated_engine, result}
    end
  end

  def stream_submit_message(
        %__MODULE__{} = engine,
        prompt,
        matched_commands \\ [],
        matched_tools \\ [],
        denied_tools \\ []
      ) do
    {updated_engine, result} =
      submit_message(engine, prompt, matched_commands, matched_tools, denied_tools)

    events =
      [
        %{type: "message_start", session_id: updated_engine.session_id, prompt: prompt},
        if(matched_commands != [], do: %{type: "command_match", commands: matched_commands}),
        if(matched_tools != [], do: %{type: "tool_match", tools: matched_tools}),
        if(denied_tools != [],
          do: %{type: "permission_denial", denials: Enum.map(denied_tools, & &1.tool_name)}
        ),
        %{type: "message_delta", text: result.output},
        %{
          type: "message_stop",
          usage: %{
            input_tokens: result.usage.input_tokens,
            output_tokens: result.usage.output_tokens
          },
          stop_reason: result.stop_reason,
          transcript_size: length(updated_engine.transcript_store.entries)
        }
      ]
      |> Enum.reject(&is_nil/1)

    {updated_engine, events}
  end

  def persist_session(%__MODULE__{} = engine) do
    store = TranscriptStore.flush(engine.transcript_store)

    session = %StoredSession{
      session_id: engine.session_id,
      messages: engine.mutable_messages,
      input_tokens: engine.total_usage.input_tokens,
      output_tokens: engine.total_usage.output_tokens
    }

    path = ClawCode.SessionStore.save_session(session)
    {%{engine | transcript_store: store}, path}
  end

  def render_summary(%__MODULE__{} = engine) do
    command_backlog = ClawCode.Commands.build_command_backlog()
    tool_backlog = ClawCode.Tools.build_tool_backlog()

    [
      "# Elixir Porting Workspace Summary",
      "",
      ClawCode.PortManifest.to_markdown(engine.manifest),
      "",
      "Command surface: #{length(command_backlog.modules)} mirrored entries",
      Enum.take(PortingBacklog.summary_lines(command_backlog), 10),
      "",
      "Tool surface: #{length(tool_backlog.modules)} mirrored entries",
      Enum.take(PortingBacklog.summary_lines(tool_backlog), 10),
      "",
      "Session id: #{engine.session_id}",
      "Conversation turns stored: #{length(engine.mutable_messages)}",
      "Permission denials tracked: #{length(engine.permission_denials)}",
      "Usage totals: in=#{engine.total_usage.input_tokens} out=#{engine.total_usage.output_tokens}",
      "Max turns: #{engine.config.max_turns}",
      "Max budget tokens: #{engine.config.max_budget_tokens}",
      "Transcript flushed: #{engine.transcript_store.flushed}"
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp compact_messages(messages, keep_last) do
    if length(messages) > keep_last, do: Enum.take(messages, -keep_last), else: messages
  end

  defp format_matches([]), do: "none"
  defp format_matches(items), do: Enum.join(items, ", ")

  defp format_output(summary_lines, false, _session_id), do: Enum.join(summary_lines, "\n")

  defp format_output(summary_lines, true, session_id) do
    JSON.encode!(%{summary: summary_lines, session_id: session_id})
  end

  defp unique_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
end
