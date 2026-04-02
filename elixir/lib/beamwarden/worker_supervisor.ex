defmodule Beamwarden.WorkerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_worker(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Beamwarden.ExternalWorker, opts})
  end
end
