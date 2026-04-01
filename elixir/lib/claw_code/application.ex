defmodule ClawCode.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {ClawCode.DaemonSupervisor, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ClawCode.Supervisor)
  end
end
