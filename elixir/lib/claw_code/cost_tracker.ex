defmodule ClawCode.CostTracker do
  @moduledoc false

  defstruct usage: %ClawCode.UsageSummary{},
            token_rate: 0.0,
            total_units: 0,
            events: []

  def new(opts \\ []) do
    %__MODULE__{
      usage: Keyword.get(opts, :usage, %ClawCode.UsageSummary{}),
      token_rate: Keyword.get(opts, :token_rate, 0.0)
    }
  end

  def estimate_cost(%__MODULE__{} = tracker) do
    total_tokens = tracker.usage.input_tokens + tracker.usage.output_tokens
    total_tokens * tracker.token_rate
  end

  def record(%__MODULE__{} = tracker, label, units) do
    %__MODULE__{
      tracker
      | total_units: tracker.total_units + units,
        events: tracker.events ++ ["#{label}:#{units}"]
    }
  end
end
