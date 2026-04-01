defmodule ClawCode.Daemon do
  @moduledoc false

  alias ClawCode.Cluster

  @client_prefix "claw_code_cli"
  @default_server_name "claw_code_daemon"

  def preflight(args) do
    cond do
      daemon_run_command?(args) ->
        args |> daemon_run_options() |> ensure_server_distribution()

      proxyable_args?(args) and configured?() ->
        ensure_client_distribution()

      true ->
        :ok
    end
  end

  def ensure_runtime(args) do
    if proxyable_args?(args) and configured?() and not current_server?() do
      case ensure_daemon_connection() do
        {:ok, _daemon} -> :ok
        {:error, _reason} -> :ok
      end
    else
      :ok
    end
  end

  def maybe_proxy(args) do
    cond do
      not proxyable_args?(args) ->
        :local

      not configured?() ->
        :local

      current_server?() ->
        :local

      true ->
        case ensure_daemon_connection() do
          {:ok, daemon} when daemon == node() ->
            :local

          {:ok, daemon} ->
            case Cluster.rpc_call(daemon, ClawCode.CLI, :run_local, [args]) do
              {:ok, result} -> {:proxy, result}
              {:error, _reason} -> :local
            end

          {:error, _reason} ->
            :local
        end
    end
  end

  def start_server(opts \\ []) do
    with :ok <- ensure_server_distribution(opts) do
      Application.put_env(:claw_code, :daemon_node, Atom.to_string(node()))
      maybe_put_cookie(opts[:cookie])
      ClawCode.ClusterDaemon.reconcile_local_runtime()
      {:ok, status_report()}
    end
  end

  def stop_server do
    case configured_node() do
      nil ->
        {:error, "No daemon node configured"}

      daemon when daemon == node() ->
        spawn(fn ->
          Process.sleep(50)
          :init.stop()
        end)

        {:ok, "Stopping current daemon node #{Atom.to_string(daemon)}"}

      daemon ->
        case ensure_daemon_connection() do
          {:ok, ^daemon} ->
            :rpc.cast(daemon, :init, :stop, [])
            {:ok, "Requested daemon shutdown for #{Atom.to_string(daemon)}"}

          {:error, reason} ->
            {:error, "Failed to reach configured daemon: #{inspect(reason)}"}
        end
    end
  end

  def block_forever do
    receive do
      {:claw_code, :stop_daemon} -> :ok
    after
      :infinity -> :ok
    end
  end

  def status do
    daemon = configured_node()

    reachable =
      cond do
        current_server?() -> Node.alive?()
        configured?() -> match?({:ok, _}, ensure_daemon_connection())
        true -> false
      end

    remote_cluster =
      if(current_server?(), do: nil, else: remote_cluster_status(daemon, reachable))

    %{
      configured?: not is_nil(daemon),
      daemon_node: daemon && Atom.to_string(daemon),
      current_node: if(Node.alive?(), do: Atom.to_string(node()), else: "local"),
      role: role_label(daemon, reachable),
      distributed?: Node.alive?(),
      daemon_reachable?: reachable,
      remote_cluster: remote_cluster
    }
  end

  def status_report do
    status = status()

    [
      "# Daemon Mode",
      "",
      "role=#{status.role}",
      "distributed=#{status.distributed?}",
      "current_node=#{status.current_node}",
      "configured_daemon_node=#{status.daemon_node || "none"}",
      "daemon_reachable=#{status.daemon_reachable?}",
      remote_line("remote_cluster_size", status.remote_cluster, :cluster_size),
      remote_line("remote_members", status.remote_cluster, :members, fn members ->
        Enum.map_join(members, ",", &Atom.to_string/1)
      end),
      remote_line("remote_routing_strategy", status.remote_cluster, :routing_strategy)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def configured?, do: not is_nil(configured_node())

  def current_server? do
    Node.alive?() and configured_node() == node()
  end

  def configured_node do
    case configured_node_label() do
      nil -> nil
      "" -> nil
      label when is_atom(label) -> label
      label when is_binary(label) -> String.to_atom(label)
    end
  end

  def configured_node_label do
    Application.get_env(:claw_code, :daemon_node) || System.get_env("CLAW_DAEMON_NODE")
  end

  def daemon_cookie do
    Application.get_env(:claw_code, :daemon_cookie) || System.get_env("CLAW_DAEMON_COOKIE")
  end

  def proxyable_args?(args) do
    case args do
      [command | _rest] ->
        command in [
          "session-start",
          "start-session",
          "session-submit",
          "session-status",
          "submit-session",
          "control-plane-status",
          "cluster-status",
          "cluster-connect",
          "cluster-disconnect",
          "start-workflow",
          "workflow-start",
          "workflow-add-step",
          "workflow-complete-step",
          "workflow-status",
          "advance-task"
        ]

      _ ->
        false
    end
  end

  def daemon_run_command?(args), do: match?(["daemon-run" | _], args)

  defp daemon_run_options(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [name: :string, cookie: :string])
    opts
  end

  defp ensure_server_distribution(opts) do
    maybe_start_epmd()

    if Node.alive?() do
      maybe_put_cookie(opts[:cookie])
      :ok
    else
      name = server_node_name(opts[:name])

      case Node.start(name, :shortnames) do
        {:ok, _pid} ->
          maybe_put_cookie(opts[:cookie])
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp ensure_client_distribution do
    maybe_start_epmd()

    if Node.alive?() do
      maybe_put_cookie(daemon_cookie())
      :ok
    else
      name = String.to_atom("#{@client_prefix}_#{System.unique_integer([:positive])}")

      case Node.start(name, :shortnames) do
        {:ok, _pid} ->
          maybe_put_cookie(daemon_cookie())
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp ensure_daemon_connection do
    case configured_node() do
      nil ->
        {:error, :not_configured}

      daemon ->
        with :ok <- ensure_client_distribution() do
          maybe_put_cookie(daemon_cookie())

          cond do
            daemon == node() ->
              {:ok, daemon}

            daemon in Node.list() ->
              {:ok, daemon}

            Node.connect(daemon) in [true, :ignored] ->
              {:ok, daemon}

            true ->
              {:error, :unreachable}
          end
        end
    end
  end

  defp remote_cluster_status(nil, _reachable), do: nil
  defp remote_cluster_status(_daemon, false), do: nil

  defp remote_cluster_status(daemon, true) do
    case Cluster.rpc_call(daemon, Cluster, :status, []) do
      {:ok, remote_status} when is_map(remote_status) -> remote_status
      _ -> nil
    end
  end

  defp role_label(daemon, _reachable) when daemon == node() and daemon != nil, do: "server"
  defp role_label(_daemon, true), do: "client"
  defp role_label(_daemon, _reachable), do: "standalone"

  defp remote_line(label, remote, key, formatter \\ & &1)
  defp remote_line(_label, nil, _key, _formatter), do: nil

  defp remote_line(label, remote, key, formatter) do
    value = Map.get(remote, key)
    "#{label}=#{formatter.(value)}"
  end

  defp maybe_start_epmd do
    System.cmd("epmd", ["-daemon"])
    :ok
  catch
    _, _ -> :ok
  end

  defp maybe_put_cookie(nil), do: :ok
  defp maybe_put_cookie(""), do: :ok

  defp maybe_put_cookie(cookie) do
    Node.set_cookie(String.to_atom(cookie))
    :ok
  end

  defp server_node_name(nil), do: String.to_atom(@default_server_name)
  defp server_node_name(""), do: String.to_atom(@default_server_name)
  defp server_node_name(name), do: String.to_atom(name)
end
