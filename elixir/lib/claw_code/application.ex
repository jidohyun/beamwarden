defmodule ClawCode.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("MIX_ENV") == "test" do
      File.rm_rf!(ClawCode.session_root())
    end

    children = [
      {ClawCode.DaemonSupervisor, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ClawCode.Supervisor)
  end
end
