defmodule Beamwarden.SessionServer do
  @moduledoc false

  use GenServer

  defstruct [
    :session_id,
    :engine,
    :last_result,
    :last_stop_reason,
    :persisted_session_path,
    submits: 0
  ]

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

  def stop(session_id) do
    GenServer.stop(via(session_id), :normal)
  end

  @impl true
  def init(session_id) do
    state = restore_state(session_id)

    Beamwarden.ClusterDaemon.claim_local_owner(
      :session,
      session_id,
      persisted_path: state.persisted_session_path
    )

    persist_runtime_snapshot(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:submit, prompt}, _from, %__MODULE__{} = state) do
    matches = Beamwarden.Runtime.route_prompt(prompt)
    command_names = matches |> Enum.filter(&(&1.kind == "command")) |> Enum.map(& &1.name)
    tool_names = matches |> Enum.filter(&(&1.kind == "tool")) |> Enum.map(& &1.name)

    denials =
      if Enum.any?(tool_names, &String.contains?(String.downcase(&1), "bash")),
        do: [
          %Beamwarden.PermissionDenial{
            tool_name: "BashTool",
            reason: "destructive shell execution remains gated in the Elixir port"
          }
        ],
        else: []

    {engine, result} =
      Beamwarden.QueryEngine.submit_message(
        state.engine,
        prompt,
        command_names,
        tool_names,
        denials
      )

    {engine, path} = Beamwarden.QueryEngine.persist_session(engine)

    next_state = %{
      state
      | engine: engine,
        last_result: result.output,
        last_stop_reason: result.stop_reason,
        persisted_session_path: path,
        submits: state.submits + 1
    }

    Beamwarden.ClusterDaemon.note_persisted(:session, state.session_id, path)
    persist_runtime_snapshot(next_state)

    {:reply, snapshot_map(next_state), next_state}
  end

  @impl true
  def handle_call(:snapshot, _from, %__MODULE__{} = state) do
    {:reply, snapshot_map(state), state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    safe_cluster_update(fn -> persist_runtime_snapshot(state) end)
    session_id = state.session_id
    safe_cluster_update(fn -> Beamwarden.ClusterDaemon.mark_stopped(:session, session_id) end)
    :ok
  end

  defp snapshot_map(%__MODULE__{} = state) do
    %{
      session_id: state.session_id,
      turns: length(state.engine.mutable_messages),
      persisted_session_path: state.persisted_session_path,
      submits: state.submits,
      stop_reason: state.last_stop_reason || "none",
      owner_node: Beamwarden.Cluster.local_owner_label(),
      usage: %{
        input_tokens: state.engine.total_usage.input_tokens,
        output_tokens: state.engine.total_usage.output_tokens
      },
      last_result: state.last_result
    }
  end

  defp via(session_id), do: {:via, Registry, {Beamwarden.SessionRegistry, session_id}}

  defp restore_state(session_id) do
    persisted_path = existing_persisted_path(session_id)

    case Beamwarden.ClusterDaemon.runtime_snapshot(:session, session_id) do
      snapshot when is_map(snapshot) ->
        engine = Beamwarden.QueryEngine.from_runtime_snapshot(snapshot)

        %__MODULE__{
          session_id: session_id,
          engine: engine,
          last_result: runtime_value(snapshot, :last_result_output),
          last_stop_reason: runtime_value(snapshot, :last_stop_reason),
          persisted_session_path:
            runtime_value(snapshot, :persisted_session_path) || persisted_path,
          submits: runtime_value(snapshot, :submits) || length(engine.mutable_messages)
        }

      _ ->
        engine =
          case persisted_path do
            path when is_binary(path) -> Beamwarden.QueryEngine.from_saved_session(session_id)
            _ -> %{Beamwarden.QueryEngine.from_workspace() | session_id: session_id}
          end

        %__MODULE__{
          session_id: session_id,
          engine: engine,
          persisted_session_path: persisted_path,
          submits: length(engine.mutable_messages)
        }
    end
  end

  defp persist_runtime_snapshot(%__MODULE__{} = state) do
    Beamwarden.ClusterDaemon.persist_runtime_snapshot(
      :session,
      state.session_id,
      runtime_snapshot(state)
    )

    :ok
  end

  defp runtime_snapshot(%__MODULE__{} = state) do
    %{
      session_id: state.session_id,
      messages: state.engine.mutable_messages,
      input_tokens: state.engine.total_usage.input_tokens,
      output_tokens: state.engine.total_usage.output_tokens,
      last_result_output: state.last_result,
      last_stop_reason: state.last_stop_reason,
      persisted_session_path: state.persisted_session_path,
      submits: state.submits
    }
  end

  defp runtime_value(snapshot, key) do
    Map.get(snapshot, key) || Map.get(snapshot, Atom.to_string(key))
  end

  defp existing_persisted_path(session_id) do
    if File.exists?(Beamwarden.session_path(session_id)),
      do: Beamwarden.session_path(session_id),
      else: nil
  end

  defp safe_cluster_update(fun) do
    fun.()
  catch
    :exit, _reason -> :ok
  end
end
