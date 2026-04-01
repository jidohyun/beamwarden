defmodule Beamwarden.ProjectOnboardingState do
  @moduledoc false

  defstruct steps: ["inspect workspace", "run mix verification", "review README"],
            completed: [],
            has_readme: false,
            has_tests: false,
            has_docs: false,
            elixir_first: true

  def mark_completed(%__MODULE__{} = state, step) do
    %{state | completed: Enum.uniq(state.completed ++ [step])}
  end

  def current do
    %__MODULE__{
      has_readme: File.exists?(Path.join(Beamwarden.repo_root(), "README.md")),
      has_tests: File.dir?(Beamwarden.test_root()),
      has_docs: File.dir?(Path.join(Beamwarden.repo_root(), "docs")),
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
