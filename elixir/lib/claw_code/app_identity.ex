defmodule ClawCode.AppIdentity do
  @moduledoc false

  @current_app :claw_code
  @future_app :beamwarden

  def current_app, do: @current_app
  def future_app, do: @future_app
  def runtime_app, do: current_app()
  def known_apps, do: [@future_app, @current_app]
  def config_apps, do: known_apps()

  def ensure_started do
    ensure_runtime_started()
  end

  def ensure_runtime_started do
    case Application.ensure_all_started(current_app()) do
      {:ok, _apps} -> :ok
      other -> other
    end
  end

  def get_env(key, default \\ nil) do
    Enum.find_value(known_apps(), default, fn app ->
      Application.get_env(app, key)
    end)
  end

  def put_env(key, value) do
    Application.put_env(current_app(), key, value)
  end

  def delete_env(key) do
    Enum.each(config_apps(), &Application.delete_env(&1, key))
    :ok
  end
end
