defmodule Beamwarden.DaemonSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Beamwarden.ClusterSupervisor, []},
      {Beamwarden.DaemonNodeMonitor, []},
      {Beamwarden.ControlPlaneSupervisor, []},
      {Beamwarden.OrchestratorSupervisor, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
