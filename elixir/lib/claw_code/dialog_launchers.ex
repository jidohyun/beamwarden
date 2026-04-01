defmodule ClawCode.DialogLaunchers do
  @moduledoc false

  def default_dialogs do
    [
      %{name: "summary", description: "Launch the Markdown summary view"},
      %{name: "parity_audit", description: "Launch the parity audit view"},
      %{name: "control_plane", description: "Launch the OTP control-plane view"}
    ]
  end

  def launch(mode, payload \\ %{}) do
    %{
      mode: mode,
      payload: payload,
      launched: true
    }
  end

  def render do
    default_dialogs()
    |> Enum.map(&"#{&1.name} — #{&1.description}")
    |> ClawCode.InteractiveHelpers.bulletize()
  end
end
