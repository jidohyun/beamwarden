defmodule ClawCode.RuntimeModeReport do
  @moduledoc false
  defstruct [:mode, :active, :detail]

  def as_text(%__MODULE__{} = report) do
    Enum.join(
      [
        "mode=#{report.mode}",
        "active=#{report.active}",
        "detail=#{report.detail}"
      ],
      "\n"
    )
  end
end

defmodule ClawCode.RemoteRuntime do
  @moduledoc false

  alias ClawCode.RuntimeModeReport

  def run_remote_mode(target),
    do: %RuntimeModeReport{
      mode: "remote",
      active: true,
      detail: "Remote control placeholder prepared for #{target}"
    }

  def run_ssh_mode(target),
    do: %RuntimeModeReport{
      mode: "ssh",
      active: true,
      detail: "SSH proxy placeholder prepared for #{target}"
    }

  def run_teleport_mode(target),
    do: %RuntimeModeReport{
      mode: "teleport",
      active: true,
      detail: "Teleport resume/create placeholder prepared for #{target}"
    }
end
