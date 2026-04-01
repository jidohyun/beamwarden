defmodule ClawCode.SessionServer do
  @moduledoc false

  use GenServer

  defstruct [:session_id, :engine, :last_result, :persisted_session_path]

  def child_spec(session_id) do
    %{
      id: {__MODULE__, session_id},
      start: {__MODULE__, :start_link, [session_id]},
      restart: :transient
    }
  end

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id, name: via(session_id))
  end

  def submit(session_id, prompt) do
    GenServer.call(via(session_id), {:submit, prompt})
  end

  def snapshot(session_id) do
    GenServer.call(via(session_id), :snapshot)
  end

  @impl true
  def init(session_id) do
    engine =
      case File.exists?(ClawCode.session_path(session_id)) do
        true -> ClawCode.QueryEngine.from_saved_session(session_id)
        false -> %{ClawCode.QueryEngine.from_workspace() | session_id: session_id}
      end

    {:ok, %__MODULE__{session_id: session_id, engine: engine}}
  end

  @impl true
  def handle_call({:submit, prompt}, _from, %__MODULE__{} = state) do
    matches = ClawCode.Runtime.route_prompt(prompt)
    command_names = matches |> Enum.filter(&(&1.kind == "command")) |> Enum.map(& &1.name)
    tool_names = matches |> Enum.filter(&(&1.kind == "tool")) |> Enum.map(& &1.name)

    denials =
      if Enum.any?(tool_names, &String.contains?(String.downcase(&1), "bash")),
        do: [
          %ClawCode.PermissionDenial{
            tool_name: "BashTool",
            reason: "destructive shell execution remains gated in the Elixir port"
          }
        ],
        else: []

    {engine, result} =
      ClawCode.QueryEngine.submit_message(
        state.engine,
        prompt,
        command_names,
        tool_names,
        denials
      )

    {engine, path} = ClawCode.QueryEngine.persist_session(engine)
    next_state = %{state | engine: engine, last_result: result, persisted_session_path: path}
    {:reply, snapshot_map(next_state), next_state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, snapshot_map(state), state}
  end

  defp snapshot_map(%__MODULE__{} = state) do
    %{
      session_id: state.session_id,
      turns: length(state.engine.mutable_messages),
      persisted_session_path: state.persisted_session_path,
      usage: %{
        input_tokens: state.engine.total_usage.input_tokens,
        output_tokens: state.engine.total_usage.output_tokens
      },
      last_result: state.last_result && state.last_result.output
    }
  end

  defp via(session_id), do: {:via, Registry, {ClawCode.SessionRegistry, session_id}}
end
