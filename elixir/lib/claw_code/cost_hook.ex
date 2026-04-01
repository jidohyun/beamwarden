defmodule ClawCode.CostHook do
  @moduledoc false

  def apply(%ClawCode.CostTracker{} = tracker, label, units) do
    ClawCode.CostTracker.record(tracker, label, units)
  end

  def warning(%ClawCode.CostTracker{} = tracker, threshold) do
    if ClawCode.CostTracker.estimate_cost(tracker) >= threshold do
      {:warn, "Estimated session cost exceeded threshold"}
    else
      :ok
    end
  end
end
