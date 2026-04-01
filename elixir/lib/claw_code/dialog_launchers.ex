defmodule ClawCode.DialogLaunchers do
  @moduledoc false

  def launch(mode, payload \\ %{}) do
    %{
      mode: mode,
      payload: payload,
      launched: true
    }
  end
end
