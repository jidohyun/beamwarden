defmodule Beamwarden.OrchestratorSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Beamwarden.RunRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Beamwarden.RunSupervisor},
      {Registry, keys: :unique, name: Beamwarden.ExternalWorkerRegistry},
      {Beamwarden.WorkerSupervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
