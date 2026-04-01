defmodule ClawCode.ControlPlaneSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: ClawCode.SessionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: ClawCode.SessionSupervisor},
      {Registry, keys: :unique, name: ClawCode.WorkflowRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: ClawCode.WorkflowSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
