defmodule ClawCode.ProjectOnboardingState do
  @moduledoc false

  defstruct steps: ["inspect workspace", "run mix verification", "review README"], completed: []

  def mark_completed(%__MODULE__{} = state, step) do
    %{state | completed: Enum.uniq(state.completed ++ [step])}
  end
end
