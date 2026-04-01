defmodule Beamwarden.CostHook do
  @moduledoc false

  def apply(%Beamwarden.CostTracker{} = tracker, label, units) do
    Beamwarden.CostTracker.record(tracker, label, units)
  end

  def warning(%Beamwarden.CostTracker{} = tracker, threshold) do
    if Beamwarden.CostTracker.estimate_cost(tracker) >= threshold do
      {:warn, "Estimated session cost exceeded threshold"}
    else
      :ok
    end
  end
end
