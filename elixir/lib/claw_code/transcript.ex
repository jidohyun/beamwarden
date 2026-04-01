defmodule ClawCode.TranscriptStore do
  @moduledoc false
  defstruct entries: [], flushed: false

  def append(%__MODULE__{entries: entries} = store, entry) do
    %{store | entries: entries ++ [entry], flushed: false}
  end

  def compact(%__MODULE__{entries: entries} = store, keep_last \\ 10) do
    trimmed = if length(entries) > keep_last, do: Enum.take(entries, -keep_last), else: entries
    %{store | entries: trimmed}
  end

  def replay(%__MODULE__{entries: entries}), do: List.to_tuple(entries)
  def flush(%__MODULE__{} = store), do: %{store | flushed: true}
end
