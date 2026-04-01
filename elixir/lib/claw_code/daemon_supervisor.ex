defmodule ClawCode.DaemonSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {ClawCode.ClusterSupervisor, []},
      {ClawCode.DaemonNodeMonitor, []},
      {ClawCode.ControlPlaneSupervisor, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
