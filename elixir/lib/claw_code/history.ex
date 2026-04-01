defmodule ClawCode.HistoryEvent do
  @moduledoc false
  defstruct [:title, :detail]
end

defmodule ClawCode.HistoryLog do
  @moduledoc false
  defstruct events: []

  def add(%__MODULE__{events: events} = log, title, detail) do
    %{log | events: events ++ [%ClawCode.HistoryEvent{title: title, detail: detail}]}
  end

  def as_markdown(%__MODULE__{events: events}) do
    Enum.join(["# Session History", ""] ++ Enum.map(events, &"- #{&1.title}: #{&1.detail}"), "\n")
  end
end
