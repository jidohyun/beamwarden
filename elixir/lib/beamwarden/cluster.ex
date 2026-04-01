defmodule Beamwarden.Cluster do
  @moduledoc false

  @rpc_timeout 5_000

  def distributed?, do: Node.alive?()

  def local_owner_label do
    if Node.alive?(), do: Atom.to_string(node()), else: "local"
  end

  def owner_node(scope, identifier) do
    nodes = member_nodes()
    Enum.at(nodes, :erlang.phash2({scope, identifier}, length(nodes)))
  end

  def member_nodes do
    if Node.alive?(), do: Enum.sort([node() | Node.list()]), else: [node()]
  end

  def quorum_size(count) when is_integer(count) and count > 0, do: div(count, 2) + 1
  def quorum_size(_count), do: 1

  def with_claim_lock(scope, identifier, fun) when is_function(fun, 0) do
    if Node.alive?() do
      :global.trans({{__MODULE__, scope, identifier}, self()}, fun, member_nodes())
    else
      fun.()
    end
  end

  def reachable_node?(target) when is_binary(target),
    do: target |> parse_owner_node() |> reachable_node?()

  def reachable_node?(nil), do: false
  def reachable_node?(target) when target == node(), do: true
  def reachable_node?(target) when is_atom(target), do: Node.alive?() and target in Node.list()

  def parse_owner_node(nil), do: nil
  def parse_owner_node(""), do: nil
  def parse_owner_node("local"), do: nil
  def parse_owner_node(target) when is_atom(target), do: target

  def parse_owner_node(target) when is_binary(target) do
    Enum.find(known_nodes(), fn candidate -> Atom.to_string(candidate) == target end)
  end

  def connect(target) do
    normalized = normalize_node(target)

    cond do
      not Node.alive?() ->
        {:error, :local_node_not_distributed}

      normalized == node() ->
        {:ok, connection_result(normalized, true, "already connected to current node")}

      true ->
        case Node.connect(normalized) do
          true -> {:ok, connection_result(normalized, true, "connected")}
          false -> {:error, connection_result(normalized, false, "connection_failed")}
          :ignored -> {:error, connection_result(normalized, false, "ignored")}
        end
    end
  end

  def disconnect(target) do
    normalized = normalize_node(target)

    cond do
      not Node.alive?() ->
        {:error, :local_node_not_distributed}

      normalized == node() ->
        {:error, :cannot_disconnect_current_node}

      true ->
        case Node.disconnect(normalized) do
          true -> {:ok, connection_result(normalized, false, "disconnected")}
          false -> {:error, connection_result(normalized, false, "disconnect_failed")}
          :ignored -> {:error, connection_result(normalized, false, "ignored")}
        end
    end
  end

  def rpc_call(target, module, function, args, timeout \\ @rpc_timeout) do
    if target == node() or not Node.alive?() do
      try do
        {:ok, apply(module, function, args)}
      rescue
        error -> {:error, {:local_call_failed, Exception.message(error)}}
      catch
        kind, reason -> {:error, {:local_call_failed, {kind, reason}}}
      end
    else
      case :rpc.call(target, module, function, args, timeout) do
        {:badrpc, reason} -> {:error, {:rpc, target, reason}}
        result -> {:ok, result}
      end
    end
  end

  def status do
    members = member_nodes()
    daemon = Beamwarden.ClusterDaemon.local_stats()
    configured_daemon_node = Beamwarden.Daemon.configured_node_label() || "none"

    daemon_role =
      cond do
        Beamwarden.Daemon.current_server?() -> "server"
        daemon_connected_to_current?() -> "client"
        true -> "standalone"
      end

    %{
      distributed?: distributed?(),
      local_node: node(),
      connected_nodes: Enum.sort(Node.list()),
      members: members,
      cluster_size: length(members),
      quorum_size: quorum_size(length(members)),
      daemon_mode: "supervised DETS-backed ownership ledger",
      daemon_role: daemon_role,
      configured_daemon_node: configured_daemon_node,
      daemon_ledger_path: daemon.ledger_path,
      daemon_runtime_path: daemon.runtime_path,
      daemon_records: daemon.records,
      daemon_runtime_snapshots: daemon.runtime_snapshots,
      routing_strategy:
        "running owner -> daemon quorum ledger -> persisted owner -> phash2 fallback"
    }
  end

  def status_report do
    status = status()

    [
      "# Cluster Status",
      "",
      "distributed=#{status.distributed?}",
      "local_node=#{status.local_node}",
      "cluster_size=#{status.cluster_size}",
      "quorum_size=#{status.quorum_size}",
      "connected_nodes=#{length(status.connected_nodes)}",
      "members=#{Enum.map_join(status.members, ",", &Atom.to_string/1)}",
      "daemon_mode=#{status.daemon_mode}",
      "daemon_role=#{status.daemon_role}",
      "configured_daemon_node=#{status.configured_daemon_node}",
      "daemon_records=#{status.daemon_records}",
      "daemon_ledger_path=#{status.daemon_ledger_path}",
      "daemon_runtime_snapshots=#{status.daemon_runtime_snapshots}",
      "daemon_runtime_path=#{status.daemon_runtime_path}",
      "routing_strategy=#{status.routing_strategy}",
      if(
        status.distributed?,
        do:
          "limit=quorum is evaluated across the currently connected BEAM subcluster, not an external consensus system",
        else:
          "limit=start the VM with --sname/--name (or Node.start/2) before using cluster-connect/disconnect"
      )
    ]
    |> Enum.join("\n")
  end

  defp daemon_connected_to_current? do
    case Beamwarden.Daemon.configured_node() do
      nil -> false
      daemon when daemon == node() -> true
      daemon -> Node.alive?() and daemon in Node.list()
    end
  end

  defp known_nodes do
    [Beamwarden.Daemon.configured_node() | member_nodes()]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_node(target) when is_atom(target), do: target
  defp normalize_node(target) when is_binary(target), do: String.to_atom(target)

  defp connection_result(target, connected, detail) do
    %{
      node: Atom.to_string(target),
      connected: connected,
      connected_nodes: Enum.map(Node.list(), &Atom.to_string/1),
      detail: detail
    }
  end
end
