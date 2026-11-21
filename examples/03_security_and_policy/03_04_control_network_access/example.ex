defmodule Jido.Realm.Host.Examples.NetworkProbe do
  alias Jido.Realm.Host

  def request(workspace, url) do
    Host.run(workspace, argv(url), timeout_ms: 5_000, output_limit: 512)
  end

  def argv(url), do: ["/bin/busybox", "wget", "-q", "-Y", "off", "-T", "2", "-O", "-", url]
end
