defmodule ClawCode.CostTracker do
  @moduledoc false
  defstruct total_units: 0, events: []

  def record(%__MODULE__{} = tracker, label, units) do
    %__MODULE__{
      total_units: tracker.total_units + units,
      events: tracker.events ++ ["#{label}:#{units}"]
    }
  end
end

defmodule ClawCode.CostHook do
  @moduledoc false

  def apply(%ClawCode.CostTracker{} = tracker, label, units) do
    ClawCode.CostTracker.record(tracker, label, units)
  end
end

defmodule ClawCode.DialogLauncher do
  @moduledoc false
  defstruct [:name, :description]
end

defmodule ClawCode.DialogLaunchers do
  @moduledoc false

  def default_dialogs do
    [
      %ClawCode.DialogLauncher{name: "summary", description: "Launch the Markdown summary view"},
      %ClawCode.DialogLauncher{name: "parity_audit", description: "Launch the parity audit view"},
      %ClawCode.DialogLauncher{name: "control_plane", description: "Launch the OTP control-plane view"}
    ]
  end

  def render do
    ClawCode.InteractiveHelpers.bulletize(
      Enum.map(default_dialogs(), &"#{&1.name} — #{&1.description}")
    )
  end
end

defmodule ClawCode.InteractiveHelpers do
  @moduledoc false

  def bulletize(items) when is_list(items) do
    Enum.map_join(items, "
", &"- #{&1}")
  end
end

defmodule ClawCode.ProjectOnboardingState do
  @moduledoc false
  defstruct [:has_readme, :has_tests, :has_docs, elixir_first: true]

  def current do
    %__MODULE__{
      has_readme: File.exists?(Path.join(ClawCode.repo_root(), "README.md")),
      has_tests: File.dir?(ClawCode.test_root()),
      has_docs: File.dir?(Path.join(ClawCode.repo_root(), "docs")),
      elixir_first: true
    }
  end

  def summary(%__MODULE__{} = state) do
    [
      "readme=#{state.has_readme}",
      "tests=#{state.has_tests}",
      "docs=#{state.has_docs}",
      "elixir_first=#{state.elixir_first}"
    ]
    |> Enum.join(" ")
  end
end

defmodule ClawCode.ReplLauncher do
  @moduledoc false

  def build_banner do
    "Elixir porting REPL is workflow-oriented; use `mix claw summary` or the control-plane commands instead."
  end
end

defmodule ClawCode.InkPanel do
  @moduledoc false

  def render(text) do
    border = String.duplicate("=", 40)
    Enum.join([border, text, border], "
")
  end
end
