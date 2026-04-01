defmodule Beamwarden.ControlPlaneSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Beamwarden.SessionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Beamwarden.SessionSupervisor},
      {Registry, keys: :unique, name: Beamwarden.WorkflowRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Beamwarden.WorkflowSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
