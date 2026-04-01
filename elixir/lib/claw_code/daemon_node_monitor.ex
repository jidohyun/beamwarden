defmodule ClawCode.DaemonNodeMonitor do
  @moduledoc false

  use GenServer

  @refresh_interval 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %{monitoring?: false}
    send(self(), :refresh_monitoring)
    {:ok, state}
  end

  @impl true
  def handle_info(:refresh_monitoring, state) do
    next_state = maybe_enable_monitoring(state)
    Process.send_after(self(), :refresh_monitoring, @refresh_interval)
    {:noreply, next_state}
  end

  def handle_info({kind, _node, _info}, state) when kind in [:nodeup, :nodedown] do
    ClawCode.ClusterDaemon.reconcile_local_runtime()
    {:noreply, state}
  end

  def handle_info({kind, _node}, state) when kind in [:nodeup, :nodedown] do
    ClawCode.ClusterDaemon.reconcile_local_runtime()
    {:noreply, state}
  end

  defp maybe_enable_monitoring(%{monitoring?: true} = state), do: state

  defp maybe_enable_monitoring(state) do
    if Node.alive?() do
      :net_kernel.monitor_nodes(true)
      ClawCode.ClusterDaemon.reconcile_local_runtime()
      %{state | monitoring?: true}
    else
      state
    end
  end
end
