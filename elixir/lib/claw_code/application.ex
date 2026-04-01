defmodule ClawCode.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ClawCode.SessionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: ClawCode.SessionSupervisor},
      {Registry, keys: :unique, name: ClawCode.WorkflowRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: ClawCode.WorkflowSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ClawCode.Supervisor)
  end
end
