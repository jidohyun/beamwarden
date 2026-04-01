defmodule ClawCode.Ink do
  @moduledoc false

  def render_banner(title) do
    "== #{title} =="
  end
end

defmodule ClawCode.InkPanel do
  @moduledoc false

  def render(text) do
    border = String.duplicate("=", 40)
    Enum.join([border, text, border], "\n")
  end
end
