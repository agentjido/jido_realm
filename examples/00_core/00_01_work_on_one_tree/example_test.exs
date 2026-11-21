Code.require_file("example.ex", __DIR__)

defmodule Jido.Realm.Host.Examples.ReportTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Realm.Host
  alias Jido.Realm.Host.Examples.Report

  test "file calls and virtual tools see the same memory tree" do
    previous = Application.fetch_env(:jido_realm, :profiles)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_realm, :profiles, value)
        :error -> Application.delete_env(:jido_realm, :profiles)
      end
    end)

    Application.put_env(:jido_realm, :profiles, %{
      memory: %{provider: :memory, policy: :full_access}
    })

    input = "Report for today\n"
    assert {:ok, workspace} = Host.open(profile: :memory)

    try do
      assert {:ok, ^input} = Report.run(workspace, input)
    after
      assert :ok = Host.close(workspace)
    end

    assert {:error, %Host.Error{code: :closed}} =
             Host.read(workspace, "reports/output data.txt")
  end
end
