defmodule Jido.Realm.Integration.TransferGuaranteesTest do
  use ExUnit.Case

  import Jido.Realm.Conformance.Scenarios

  alias Jido.Realm.Conformance.{AgentJobs, BindingFixture, Files, Scenarios}

  realm_case "01.04 a move preserves its source when the destination changes before verification",
    agent: AgentJobs.Pair,
    cases: [
      local_to_memory: [
        source: static_fixture(:local),
        target: static_fixture(:memory, hook: pause_after_create(self()))
      ],
      memory_to_local: [
        source: static_fixture(:memory),
        target: static_fixture(:local, hook: pause_after_create(self()))
      ]
    ] do
    %{
      agent: mover,
      instance: instance,
      bindings: bindings,
      observe: %{source: source, target: target}
    } ->
      Files.assert_reply(mover, :create, "draft", %{realm: :source, content: "verified version"})
      writer = Scenarios.start_agent(instance, AgentJobs.Pair, bindings)

      move =
        Task.async(fn ->
          AgentJobs.rejected(mover, :move, :transfer_verification_failed, %{
            path: "draft",
            to: "final"
          })
        end)

      assert_receive {:written, worker}, 2_000
      Files.assert_reply(writer, :edit, "final", %{realm: :target, content: "another writer"})
      send(worker, :continue)
      Task.await(move)

      assert source.("draft") == {:ok, "verified version"}
      assert target.("final") == {:ok, "another writer"}
  end

  realm_case "01.05 streams a multi-megabyte binary with bounded chunks and an exact tail",
    agent: AgentJobs.Pair,
    cases: [
      disk_to_disk: [
        source: static_fixture(:local, hook: observe_chunks(self())),
        target: static_fixture(:local)
      ]
    ] do
    %{agent: agent, placements: %{source: source, target: target}} ->
      bytes = :binary.copy(<<0, 255, 7, 130>>, 786_432) <> <<9, 0, 255>>
      source.seed.("compiled.bin", bytes)

      AgentJobs.succeeded(agent, :stream, %{
        path: "compiled.bin",
        to: "received.bin",
        chunk_size: 65_536
      })

      for _ <- 1..48, do: assert_receive({:chunk, 65_536})
      assert_receive {:chunk, 3}
      refute_received {:chunk, _}
      assert target.observe.("received.bin") == {:ok, bytes}
      assert source.observe.("compiled.bin") == {:ok, bytes}
  end

  realm_case "01.03 two agents copying different build outputs get one destination winner",
    agent: AgentJobs.Pair,
    cases: [
      local_destination: [source: static_fixture(:memory), target: static_fixture(:local)],
      memory_destination: [source: static_fixture(:local), target: static_fixture(:memory)]
    ] do
    %{
      agent: first,
      instance: instance,
      bindings: bindings,
      placements: %{source: source, target: target}
    } ->
      second = Scenarios.start_agent(instance, AgentJobs.Pair, bindings)
      source.seed.("first", "first build")
      source.seed.("second", "second build")

      replies =
        [{first, "first", "first build"}, {second, "second", "second build"}]
        |> Task.async_stream(fn {agent, path, bytes} ->
          {bytes, AgentJobs.call(agent, :copy, %{path: path, to: "review"})}
        end)
        |> Enum.map(fn {:ok, {bytes, {:ok, reply}}} -> {reply.status, bytes, reply} end)
        |> Enum.sort()

      assert [
               {:committed, winner, _},
               {:failed, _, %{error: %{details: %{reason: :already_exists}}}}
             ] = replies

      assert target.observe.("review") == {:ok, winner}
      assert source.observe.("first") == {:ok, "first build"}
      assert source.observe.("second") == {:ok, "second build"}
  end

  defp static_fixture(kind, opts \\ []), do: {BindingFixture, [kind: kind, mode: :static] ++ opts}

  defp pause_after_create(test) do
    fn
      :create, "final", _, run ->
        :ok = run.()
        send(test, {:written, self()})

        receive do
          :continue -> :ok
        after
          3_000 -> {:error, :backend_error}
        end

      _, _, _, run ->
        run.()
    end
  end

  defp observe_chunks(test) do
    fn
      :read_stream, _, 65_536, run ->
        {:ok, chunks} = run.()

        {:ok,
         Stream.map(chunks, fn chunk ->
           send(test, {:chunk, byte_size(chunk)})
           chunk
         end)}

      _, _, _, run ->
        run.()
    end
  end
end
