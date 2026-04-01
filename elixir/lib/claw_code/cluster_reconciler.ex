defmodule ClawCode.ClusterReconciler do
  @moduledoc false

  use GenServer

  @interval 2_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_reconcile()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    try do
      ClawCode.ClusterDaemon.reconcile_local_runtime()
    catch
      :exit, _reason -> :ok
    end

    schedule_reconcile()
    {:noreply, state}
  end

  defp schedule_reconcile do
    Process.send_after(self(), :reconcile, @interval)
  end
end
