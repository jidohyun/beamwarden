defmodule Beamwarden.LogBroker do
  @moduledoc false

  use GenServer

  alias Beamwarden.Cluster
  alias Beamwarden.EventStore

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def append(run_id, event) do
    GenServer.call(__MODULE__, {:append, run_id, event})
  catch
    :exit, _reason -> EventStore.append(run_id, event)
  end

  def subscribe(run_id, after_seq, opts \\ []) when is_integer(after_seq) and after_seq >= 0 do
    pid = Keyword.get(opts, :pid, self())

    GenServer.call(__MODULE__, {:subscribe, run_id, pid, after_seq})
  catch
    :exit, _reason -> {:error, :broker_unavailable}
  end

  def unsubscribe(run_id, opts \\ []) do
    pid = Keyword.get(opts, :pid, self())

    GenServer.call(__MODULE__, {:unsubscribe, run_id, pid})
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscribers: %{}}}
  end

  @impl true
  def handle_call({:append, run_id, event}, _from, state) do
    envelope = EventStore.append(run_id, event)
    live_event = Map.put(envelope, "source", "live")

    state
    |> subscribers_for(run_id)
    |> Enum.each(fn pid -> send(pid, {:beamwarden_log_broker, run_id, live_event}) end)

    {:reply, envelope, state}
  end

  def handle_call({:subscribe, run_id, pid, after_seq}, _from, state) do
    {:ok, backlog} = EventStore.list_since(run_id, after_seq)
    cursor = max(after_seq, last_seq(backlog))

    {subscribers, changed?} = ensure_subscription(state.subscribers, run_id, pid)
    next_state = if changed?, do: %{state | subscribers: subscribers}, else: state

    {:reply,
     {:ok,
      %{
        backlog: Enum.map(backlog, &Map.put(&1, "source", "replay")),
        cursor: cursor,
        broker_node: Cluster.local_owner_label()
      }}, next_state}
  end

  def handle_call({:unsubscribe, run_id, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: drop_subscription(state.subscribers, run_id, pid)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: prune_subscriber(state.subscribers, pid, ref)}}
  end

  defp ensure_subscription(subscribers, run_id, pid) do
    run_subscribers = Map.get(subscribers, run_id, %{})

    case Map.get(run_subscribers, pid) do
      nil ->
        ref = Process.monitor(pid)
        {Map.put(subscribers, run_id, Map.put(run_subscribers, pid, ref)), true}

      _ref ->
        {subscribers, false}
    end
  end

  defp drop_subscription(subscribers, run_id, pid) do
    run_subscribers = Map.get(subscribers, run_id, %{})

    case Map.pop(run_subscribers, pid) do
      {nil, _} ->
        subscribers

      {ref, remaining} ->
        Process.demonitor(ref, [:flush])

        if map_size(remaining) == 0 do
          Map.delete(subscribers, run_id)
        else
          Map.put(subscribers, run_id, remaining)
        end
    end
  end

  defp prune_subscriber(subscribers, pid, ref) do
    subscribers
    |> Enum.reduce(%{}, fn {run_id, run_subscribers}, acc ->
      remaining =
        run_subscribers
        |> Enum.reject(fn {subscriber_pid, subscriber_ref} ->
          subscriber_pid == pid and subscriber_ref == ref
        end)
        |> Map.new()

      if map_size(remaining) == 0, do: acc, else: Map.put(acc, run_id, remaining)
    end)
  end

  defp subscribers_for(state, run_id) do
    state.subscribers
    |> Map.get(run_id, %{})
    |> Map.keys()
  end

  defp last_seq([]), do: 0
  defp last_seq(events), do: events |> List.last() |> event_seq() || 0

  defp value(nil, _key), do: nil
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp event_seq(nil), do: nil
  defp event_seq(entry), do: value(entry, :event_seq) || value(entry, :seq)
end
