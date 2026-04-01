defmodule Beamwarden.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("MIX_ENV") == "test" do
      File.rm_rf!(Beamwarden.session_root())
    end

    children = [
      {Beamwarden.DaemonSupervisor, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Beamwarden.Supervisor)
  end
end
