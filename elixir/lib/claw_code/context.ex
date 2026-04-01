defmodule ClawCode.PortContext do
  @moduledoc false
  defstruct [
    :source_root,
    :tests_root,
    :assets_root,
    :archive_root,
    :elixir_file_count,
    :test_file_count,
    :asset_file_count,
    :archive_available
  ]
end

defmodule ClawCode.Context do
  @moduledoc false

  alias ClawCode.PortContext

  def build(_base \\ ClawCode.project_root()) do
    source_root = ClawCode.source_root()
    tests_root = ClawCode.test_root()
    assets_root = ClawCode.assets_root()
    archive_root = ClawCode.archive_root()

    %PortContext{
      source_root: source_root,
      tests_root: tests_root,
      assets_root: assets_root,
      archive_root: archive_root,
      elixir_file_count: count_files(source_root, ["**/*.ex"]),
      test_file_count: count_files(tests_root, ["**/*.exs"]),
      asset_file_count: count_files(assets_root, ["**/*"]),
      archive_available: File.dir?(archive_root)
    }
  end

  def render(%PortContext{} = context) do
    Enum.join(
      [
        "Source root: #{context.source_root}",
        "Test root: #{context.tests_root}",
        "Assets root: #{context.assets_root}",
        "Archive root: #{context.archive_root}",
        "Elixir files: #{context.elixir_file_count}",
        "Test files: #{context.test_file_count}",
        "Assets: #{context.asset_file_count}",
        "Archive available: #{context.archive_available}"
      ],
      "\n"
    )
  end

  defp count_files(root, patterns) do
    patterns
    |> Enum.flat_map(&Path.wildcard(Path.join(root, &1), match_dot: false))
    |> Enum.filter(&File.regular?/1)
    |> length()
  end
end
