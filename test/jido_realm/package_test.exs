defmodule Jido.Realm.PackageTest do
  use ExUnit.Case, async: true

  test "Realm, Shell and VFS start as separate applications and own their modules" do
    apps = [:jido_realm, :jido_shell, :jido_vfs]
    started = Application.started_applications()

    for app <- apps do
      assert Enum.count(started, &(elem(&1, 0) == app)) == 1
    end

    for {module, owner} <- [
          {Jido.Realm.Host, :jido_realm},
          {Jido.Shell.CommandRunner, :jido_shell},
          {Jido.VFS.Adapter.InMemory, :jido_vfs}
        ] do
      assert Enum.filter(apps, &(module in Application.spec(&1, :modules))) == [owner]
    end
  end
end
