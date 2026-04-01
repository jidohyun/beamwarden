defmodule ClawCode.DirectModeReport do
  @moduledoc false
  defstruct [:mode, :target, :active]

  def as_text(%__MODULE__{} = report) do
    Enum.join(["mode=#{report.mode}", "target=#{report.target}", "active=#{report.active}"], "\n")
  end
end

defmodule ClawCode.DirectModes do
  @moduledoc false

  alias ClawCode.DirectModeReport

  def run_direct_connect(target),
    do: %DirectModeReport{mode: "direct-connect", target: target, active: true}

  def run_deep_link(target),
    do: %DirectModeReport{mode: "deep-link", target: target, active: true}
end
