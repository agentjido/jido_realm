Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Examples.SharedCheckoutTest do
  use ExUnit.Case, async: false

  alias Jido.Realm.Examples.SharedCheckout, as: Example

  @moduletag :docker
  @moduletag :tmp_dir
  @moduletag timeout: 120_000
  @image "bash:5.2"

  setup %{tmp_dir: root} do
    checkout = Path.join(root, "checkout")
    File.mkdir!(checkout)
    assert {"", 0} = System.cmd("git", ["init", "--quiet", checkout])
    File.write!(Path.join(checkout, "source.txt"), "41\n")
    stores = %{"reports" => Path.join(root, "snapshots")}
    previous = Application.fetch_env(:jido_realm, :stores)
    Application.put_env(:jido_realm, :stores, stores)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_realm, :stores, value)
        :error -> Application.delete_env(:jido_realm, :stores)
      end
    end)

    start_supervised!({Jido, name: __MODULE__})

    %{
      checkout: checkout,
      stores: stores,
      profile: %{
        provider: :docker,
        image: @image,
        store: "reports",
        tools: ["bash"],
        policy: [:read, :write, :execute, :save]
      }
    }
  end

  test "a tool and an agent share a checkout and hand off the checked tree", context do
    profile = Map.put(context.profile, :checkout, context.checkout)
    {:ok, session} = Example.session(profile)
    writer = Example.start_agent(__MODULE__, session, [:open, :close, :read, :write, :run, :save])
    observer = Example.start_agent(__MODULE__, session, [:read, :run])

    assert %{capabilities: caps} = result(writer, "realm.open")
    assert :snapshots in caps
    assert :bash in caps

    assert %{status: :timed_out} = handoff(writer, :wait, "timeout-check")
    {:ok, checkout_key} = Jido.Realm.Host.Sandbox.Files.checkout_key(context.checkout)
    filter = ["--filter", "label=dev.jido.realm.checkout=" <> checkout_key]
    assert {"", 0} = System.cmd("docker", ["ps", "--quiet" | filter])

    assert %{status: :failed, exit_code: 1} = handoff(writer, :check, "check-before")

    assert %{revision: old} = result(writer, "realm.file.read_revision", %{path: "source.txt"})

    result(writer, "realm.file.edit_revision", %{
      path: "source.txt",
      revision: old,
      content: "42\n"
    })

    assert_error(writer, "realm.file.edit_revision", :conflict, %{
      path: "source.txt",
      revision: old,
      content: "43\n"
    })

    assert %{status: :succeeded, tree_revision: revision} = handoff(writer, :check, "check-after")
    assert is_binary(revision)

    assert_error(observer, "checkout.handoff", :permission_denied, %{
      operation: :check,
      id: "check-after"
    })

    assert %{content: "verified 42\n"} = result(writer, "realm.file.read", %{path: "report.txt"})
    assert File.read!(Path.join(context.checkout, "report.txt")) == "verified 42\n"

    assert_error(writer, "realm.file.create", :already_exists, %{
      path: "report.txt",
      content: "duplicate"
    })

    snapshot = handoff(writer, :save, "check-after")
    assert snapshot.format == 1
    result(writer, "realm.file.edit", %{path: "report.txt", content: "unverified\n"})

    assert_error(writer, "checkout.handoff", :stale_source, %{operation: :save, id: "check-after"})

    assert {:ok, %{status: :committed}} = Example.call(writer, "realm.close")
    assert File.read!(Path.join(context.checkout, "report.txt")) == "unverified\n"
    assert {"", 0} = System.cmd("docker", ["ps", "--all", "--quiet" | filter])

    assert File.regular?(Path.join(Map.fetch!(context.stores, snapshot.store), snapshot.digest))
    reader_profile = Map.put(context.profile, :policy, [:read, :import, :execute])
    assert review_in_fresh_beam(reader_profile, snapshot, context.stores) == "verified 42\n"
  end

  defp result(agent, type, data \\ %{}) do
    assert {:ok, %{status: :committed, reply: %{data: result}}} = Example.call(agent, type, data)
    result
  end

  defp handoff(agent, operation, id),
    do: result(agent, "checkout.handoff", %{operation: operation, id: id})

  defp assert_error(agent, type, reason, data) do
    assert {:ok, %{status: :failed, error: %{details: %{reason: ^reason}}}} =
             Example.call(agent, type, data)
  end

  defp review_in_fresh_beam(profile, snapshot, stores) do
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", Path.expand(&1) |> to_charlist()])

    {:ok, peer, _} =
      :peer.start_link(%{
        connection: :standard_io,
        args: [~c"+S", ~c"2:2" | paths],
        wait_boot: 15_000
      })

    try do
      assert {:ok, _} = :peer.call(peer, Application, :ensure_all_started, [:jido_realm], 15_000)
      :peer.call(peer, Code, :require_file, [Path.join(__DIR__, "example.ex")], 15_000)

      :peer.call(
        peer,
        Example,
        :review,
        [profile, JSON.decode!(JSON.encode!(snapshot)), stores],
        45_000
      )
    after
      :peer.stop(peer)
    end
  end
end
