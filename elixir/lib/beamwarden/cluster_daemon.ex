defmodule Beamwarden.ClusterDaemon do
  @moduledoc false

  use GenServer

  alias Beamwarden.Cluster

  @ets_table :beamwarden_cluster_claims
  @dets_table :beamwarden_cluster_ledger
  @runtime_dets_table :beamwarden_cluster_runtime
  @lease_ttl_ms 15_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def claim_local_owner(scope, identifier, opts \\ []) do
    Cluster.with_claim_lock(scope, identifier, fn ->
      GenServer.call(__MODULE__, {:claim_local_owner, scope, identifier, Map.new(opts)})
    end)
  end

  def note_persisted(scope, identifier, path, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:note_persisted, scope, identifier, path, Map.new(opts)}
    )
  end

  def mark_stopped(scope, identifier) do
    GenServer.call(__MODULE__, {:mark_stopped, scope, identifier})
  end

  def local_record(scope, identifier) do
    GenServer.call(__MODULE__, {:local_record, scope, identifier})
  end

  def local_cluster_view(scope, identifier) do
    %{
      node: node(),
      members: Cluster.member_nodes(),
      record: local_record(scope, identifier)
    }
  end

  def resolve_owner(scope, identifier, persisted_owner \\ nil) do
    view = cluster_view(scope, identifier)
    freshest = freshest_record(view.records)
    freshest_reachable = freshest_reachable_record(view.records)
    deterministic_owner = Cluster.owner_node(scope, identifier)

    cond do
      freshest && record_reachable?(freshest) ->
        owner_target(freshest.owner_node)

      freshest_reachable ->
        owner_target(freshest_reachable.owner_node)

      freshest && quorum_met?(view) ->
        deterministic_owner

      Cluster.reachable_node?(persisted_owner) ->
        Cluster.parse_owner_node(persisted_owner)

      true ->
        deterministic_owner
    end
  end

  def merge_remote_record(record) when is_map(record) do
    GenServer.call(__MODULE__, {:merge_remote_record, record})
  end

  def reconcile_local_runtime do
    GenServer.call(__MODULE__, :reconcile_local_runtime)
  end

  def persist_runtime_snapshot(scope, identifier, snapshot) when is_map(snapshot) do
    GenServer.call(__MODULE__, {:persist_runtime_snapshot, scope, identifier, snapshot})
  end

  def runtime_snapshot(scope, identifier) do
    GenServer.call(__MODULE__, {:runtime_snapshot, scope, identifier})
  end

  def ledger_snapshot do
    GenServer.call(__MODULE__, :ledger_snapshot)
  end

  def local_stats do
    GenServer.call(__MODULE__, :local_stats)
  end

  @impl true
  def init(_opts) do
    File.mkdir_p!(Beamwarden.cluster_node_root())

    table =
      case :ets.whereis(@ets_table) do
        :undefined -> :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
        table -> table
      end

    {:ok, dets} =
      :dets.open_file(@dets_table, file: String.to_charlist(Beamwarden.cluster_ledger_path()))

    {:ok, runtime_dets} =
      :dets.open_file(@runtime_dets_table,
        file: String.to_charlist(Beamwarden.cluster_runtime_path())
      )

    load_dets_into_ets(dets, table)

    {:ok,
     %{
       table: table,
       dets: dets,
       runtime_dets: runtime_dets,
       ledger_path: Beamwarden.cluster_ledger_path(),
       runtime_path: Beamwarden.cluster_runtime_path()
     }}
  end

  @impl true
  def handle_call({:claim_local_owner, scope, identifier, attrs}, _from, state) do
    existing = lookup_record(state.table, scope, identifier)
    owner_node = Cluster.local_owner_label()

    record =
      cond do
        existing && existing.owner_node != owner_node && record_reachable?(existing) ->
          touch_record(existing)

        true ->
          existing
          |> build_claim_record(scope, identifier, owner_node, attrs)
      end

    saved = maybe_store_record(state, record)
    maybe_broadcast(saved)
    {:reply, saved, state}
  end

  @impl true
  def handle_call({:note_persisted, scope, identifier, path, attrs}, _from, state) do
    existing = lookup_record(state.table, scope, identifier)
    owner_node = attrs[:owner_node] || Cluster.local_owner_label()

    record =
      existing
      |> build_claim_record(scope, identifier, owner_node, Map.put(attrs, :persisted_path, path))
      |> Map.put(:running, local_running?(scope, identifier))

    saved = maybe_store_record(state, record)
    maybe_broadcast(saved)
    {:reply, saved, state}
  end

  @impl true
  def handle_call({:mark_stopped, scope, identifier}, _from, state) do
    updated =
      case lookup_record(state.table, scope, identifier) do
        nil ->
          nil

        existing ->
          updated_at = now_ms()

          existing
          |> Map.put(:running, false)
          |> Map.put(:lease_expires_at, updated_at)
          |> Map.put(:updated_at, updated_at)
          |> then(&maybe_store_record(state, &1))
      end

    clear_runtime_snapshot(state.runtime_dets, scope, identifier)

    {:reply, updated, state}
  end

  @impl true
  def handle_call({:local_record, scope, identifier}, _from, state) do
    {:reply, lookup_record(state.table, scope, identifier), state}
  end

  @impl true
  def handle_call({:merge_remote_record, record}, _from, state) do
    saved = maybe_store_record(state, normalize_record(record))
    {:reply, saved, state}
  end

  @impl true
  def handle_call(:reconcile_local_runtime, _from, state) do
    now = now_ms()

    desired =
      runtime_records(:session, state) ++ runtime_records(:workflow, state)

    desired_keys =
      desired
      |> Enum.map(&record_key/1)
      |> MapSet.new()

    Enum.each(desired, fn record ->
      maybe_store_record(state, Map.put(record, :updated_at, now))
    end)

    local_owner = Cluster.local_owner_label()

    state.table
    |> :ets.tab2list()
    |> Enum.map(fn {_key, record} -> record end)
    |> Enum.filter(fn record ->
      record.owner_node == local_owner and record.running and
        not MapSet.member?(desired_keys, record_key(record))
    end)
    |> Enum.each(fn record ->
      maybe_store_record(
        state,
        record
        |> Map.put(:running, false)
        |> Map.put(:lease_expires_at, now)
        |> Map.put(:updated_at, now)
      )
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:persist_runtime_snapshot, scope, identifier, snapshot}, _from, state) do
    normalized =
      snapshot
      |> normalize_runtime_snapshot(scope, identifier)
      |> then(&maybe_store_runtime_snapshot(state, &1))

    {:reply, normalized, state}
  end

  @impl true
  def handle_call({:runtime_snapshot, scope, identifier}, _from, state) do
    {:reply, lookup_runtime_snapshot(state.runtime_dets, scope, identifier), state}
  end

  @impl true
  def handle_call(:ledger_snapshot, _from, state) do
    snapshot =
      state.table
      |> :ets.tab2list()
      |> Enum.map(fn {_key, record} -> record end)
      |> Enum.sort_by(&{&1.scope, &1.identifier, -&1.epoch})

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call(:local_stats, _from, state) do
    {:reply,
     %{
       ledger_path: state.ledger_path,
       runtime_path: state.runtime_path,
       records: :ets.info(state.table, :size),
       runtime_snapshots: :dets.info(state.runtime_dets, :size)
     }, state}
  end

  @impl true
  def terminate(_reason, state) do
    :dets.close(state.dets)
    :dets.close(state.runtime_dets)
    :ok
  end

  defp cluster_view(scope, identifier) do
    views =
      Cluster.member_nodes()
      |> Enum.flat_map(fn target ->
        case Cluster.rpc_call(target, __MODULE__, :local_cluster_view, [scope, identifier]) do
          {:ok, view} when is_map(view) -> [view]
          _ -> []
        end
      end)

    known_cluster_size =
      views
      |> Enum.map(fn view -> length(view.members || []) end)
      |> Kernel.++([length(Cluster.member_nodes())])
      |> Enum.max()

    %{
      views: views,
      records: Enum.map(views, & &1.record) |> Enum.reject(&is_nil/1),
      acknowledgements: length(views),
      quorum_size: Cluster.quorum_size(known_cluster_size)
    }
  end

  defp quorum_met?(view), do: view.acknowledgements >= view.quorum_size

  defp runtime_records(scope, state) do
    owner_node = Cluster.local_owner_label()

    local_running_ids(scope)
    |> Enum.map(fn identifier ->
      existing = lookup_record(state.table, scope, identifier)
      now = now_ms()

      %{
        scope: scope,
        identifier: identifier,
        owner_node: owner_node,
        epoch: next_epoch(existing, owner_node),
        running: true,
        persisted_path: persisted_path_for(scope, identifier, existing),
        updated_at: now,
        lease_expires_at: now + @lease_ttl_ms,
        source: :runtime
      }
    end)
  end

  defp local_running_ids(:session) do
    select_registry_keys(Beamwarden.SessionRegistry)
  end

  defp local_running_ids(:workflow) do
    select_registry_keys(Beamwarden.WorkflowRegistry)
  end

  defp select_registry_keys(registry) do
    if Process.whereis(registry) do
      Registry.select(registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    else
      []
    end
  end

  defp local_running?(scope, identifier) do
    identifier in local_running_ids(scope)
  end

  defp persisted_path_for(:session, identifier, existing) do
    cond do
      File.exists?(Beamwarden.session_path(identifier)) -> Beamwarden.session_path(identifier)
      existing -> existing.persisted_path
      true -> nil
    end
  end

  defp persisted_path_for(:workflow, identifier, existing) do
    cond do
      File.exists?(Beamwarden.workflow_path(identifier)) -> Beamwarden.workflow_path(identifier)
      existing -> existing.persisted_path
      true -> nil
    end
  end

  defp maybe_broadcast(nil), do: :ok

  defp maybe_broadcast(record) do
    if Node.alive?() and Process.whereis(Beamwarden.ClusterTaskSupervisor) do
      Enum.each(Node.list(), fn target ->
        Task.Supervisor.start_child(Beamwarden.ClusterTaskSupervisor, fn ->
          Cluster.rpc_call(target, __MODULE__, :merge_remote_record, [record])
        end)
      end)
    end

    :ok
  end

  defp build_claim_record(existing, scope, identifier, owner_node, attrs) do
    now = now_ms()

    %{
      scope: scope,
      identifier: identifier,
      owner_node: owner_node,
      epoch: next_epoch(existing, owner_node),
      running: Map.get(attrs, :running, true),
      persisted_path: Map.get(attrs, :persisted_path, existing && existing.persisted_path),
      updated_at: now,
      lease_expires_at: now + @lease_ttl_ms,
      source: Map.get(attrs, :source, :claim)
    }
  end

  defp maybe_store_record(_state, nil), do: nil

  defp maybe_store_record(state, record) do
    record = normalize_record(record)
    key = record_key(record)
    current = lookup_record(state.table, record.scope, record.identifier)

    if current == nil or fresher?(record, current) or equivalent_owner?(record, current) do
      true = :ets.insert(state.table, {key, record})
      :ok = :dets.insert(state.dets, {key, record})
      :ok = :dets.sync(state.dets)
      record
    else
      current
    end
  end

  defp equivalent_owner?(left, right) do
    left.owner_node == right.owner_node and left.scope == right.scope and
      left.identifier == right.identifier
  end

  defp lookup_record(table, scope, identifier) do
    case :ets.lookup(table, {scope, identifier}) do
      [{{^scope, ^identifier}, record}] -> normalize_record(record)
      _ -> nil
    end
  end

  defp load_dets_into_ets(dets, table) do
    :dets.foldl(
      fn {key, record}, :ok ->
        :ets.insert(table, {key, normalize_record(record)})
        :ok
      end,
      :ok,
      dets
    )
  end

  defp maybe_store_runtime_snapshot(_state, nil), do: nil

  defp maybe_store_runtime_snapshot(state, snapshot) do
    key = runtime_snapshot_key(snapshot.scope, snapshot.identifier)
    :ok = :dets.insert(state.runtime_dets, {key, snapshot})
    :ok = :dets.sync(state.runtime_dets)
    snapshot
  end

  defp lookup_runtime_snapshot(runtime_dets, scope, identifier) do
    case :dets.lookup(runtime_dets, runtime_snapshot_key(scope, identifier)) do
      [{_key, snapshot}] -> snapshot
      [] -> nil
    end
  end

  defp clear_runtime_snapshot(runtime_dets, scope, identifier) do
    :ok = :dets.delete(runtime_dets, runtime_snapshot_key(scope, identifier))
    :ok
  end

  defp freshest_record([]), do: nil

  defp freshest_record(records) do
    Enum.reduce(records, fn record, best ->
      if fresher?(record, best), do: record, else: best
    end)
  end

  defp freshest_reachable_record(records) do
    records
    |> Enum.filter(&record_reachable?/1)
    |> case do
      [] -> nil
      reachable -> freshest_record(reachable)
    end
  end

  defp fresher?(left, right) do
    cond do
      left.epoch != right.epoch -> left.epoch > right.epoch
      left.running != right.running -> left.running
      left.updated_at != right.updated_at -> left.updated_at > right.updated_at
      true -> left.owner_node >= right.owner_node
    end
  end

  defp next_epoch(nil, _owner_node), do: 1
  defp next_epoch(%{owner_node: owner_node, epoch: epoch}, owner_node), do: epoch
  defp next_epoch(%{epoch: epoch}, _owner_node), do: epoch + 1

  defp record_key(record), do: {record.scope, record.identifier}
  defp runtime_snapshot_key(scope, identifier), do: {scope, identifier}

  defp touch_record(record) do
    now = now_ms()

    record
    |> Map.put(:updated_at, now)
    |> Map.put(:lease_expires_at, now + @lease_ttl_ms)
  end

  defp normalize_record(record) do
    %{
      scope: Map.fetch!(record, :scope),
      identifier: Map.fetch!(record, :identifier),
      owner_node: Map.fetch!(record, :owner_node),
      epoch: Map.get(record, :epoch, 1),
      running: Map.get(record, :running, false),
      persisted_path: Map.get(record, :persisted_path),
      updated_at: Map.get(record, :updated_at, now_ms()),
      lease_expires_at: Map.get(record, :lease_expires_at, now_ms()),
      source: Map.get(record, :source, :claim)
    }
  end

  defp normalize_runtime_snapshot(snapshot, scope, identifier) do
    snapshot
    |> Map.new()
    |> Map.put(:scope, scope)
    |> Map.put(:identifier, identifier)
    |> Map.put_new(:updated_at, now_ms())
  end

  defp owner_target("local"), do: node()
  defp owner_target(owner_node), do: Cluster.parse_owner_node(owner_node) || node()

  defp record_reachable?(record) do
    case record.owner_node do
      "local" -> true
      owner_node -> Cluster.reachable_node?(owner_node)
    end
  end

  defp now_ms, do: System.system_time(:millisecond)
end
