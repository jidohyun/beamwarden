defmodule ClawCode.Cluster do
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

  def reachable_node?(target) when is_binary(target),
    do: target |> parse_owner_node() |> reachable_node?()

  def reachable_node?(nil), do: false
  def reachable_node?(target) when target == node(), do: true
  def reachable_node?(target) when is_atom(target), do: Node.alive?() and target in Node.list()

  def parse_owner_node(nil), do: nil
  def parse_owner_node(""), do: nil
  def parse_owner_node("local"), do: nil
  def parse_owner_node(target) when is_atom(target), do: target
  def parse_owner_node(target) when is_binary(target), do: String.to_atom(target)

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

    %{
      distributed?: distributed?(),
      local_node: node(),
      connected_nodes: Enum.sort(Node.list()),
      members: members,
      cluster_size: length(members),
      routing_strategy: "running owner -> persisted owner -> phash2 fallback"
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
      "connected_nodes=#{length(status.connected_nodes)}",
      "members=#{Enum.map_join(status.members, ",", &Atom.to_string/1)}",
      "routing_strategy=#{status.routing_strategy}",
      if(
        status.distributed?,
        do:
          "limit=ephemeral CLI invocations do not keep a BEAM cluster alive after the command exits",
        else:
          "limit=start the VM with --sname/--name (or Node.start/2) before using cluster-connect/disconnect"
      )
    ]
    |> Enum.join("\n")
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
