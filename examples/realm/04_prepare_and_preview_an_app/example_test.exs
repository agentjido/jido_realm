defmodule Jido.Realm.AppleContainerShowcaseTest do
  use ExUnit.Case

  alias Jido.Realm.Conformance.{Files, LocalFixture}

  @moduletag :realm_example
  @moduletag :apple_container

  test "agent-authored setup and application run in an Apple Container and serve a preview" do
    %{runtime_options: options, observe: observe} = LocalFixture.prepare(%{})
    root = Keyword.fetch!(options, :root)
    server = Files.start_agent(__MODULE__, options)
    image = System.get_env("JIDO_REALM_APPLE_IMAGE", "alpine:latest")
    assert_cached_image(image)
    nonce = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    outside = Path.join(Path.dirname(root), "jido-realm-sentinel-" <> nonce)
    File.write!(outside, "host only", [:exclusive])
    on_exit(fn -> File.rm!(outside) end)

    Files.assert_reply(server, :create, "setup.sh", %{
      content: """
      set -eu
      test ! -e "$1"
      test -z "${REALM_HOST_SENTINEL:-}"
      test "$(ls /sys/class/net)" = lo
      if (printf 'probe' > /realm-root-probe) 2>/dev/null; then exit 1; fi
      printf '%s\n' 'prepared by Realm setup' > prepared.txt
      """
    })

    Files.assert_reply(server, :create, "app.sh", %{
      content: """
      set -eu
      tr '[:lower:]' '[:upper:]' < prepared.txt > /tmp/report
      cat > /tmp/respond <<'RESPOND'
      #!/bin/sh
      IFS= read -r request
      printf 'HTTP/1.1 200 OK\\r\\nContent-Type: text/plain\\r\\nContent-Length: %s\\r\\nConnection: close\\r\\n\\r\\n' "$(wc -c </tmp/report)"
      cat /tmp/report
      RESPOND
      chmod +x /tmp/respond
      exec busybox nc -lk -p "$PORT" -e /tmp/respond
      """
    })

    setup = "realm-setup-" <> nonce
    register_cleanup(setup)

    create!(setup, root, image, ["--network", "none", "--no-dns", "--read-only"], "/bin/sh", [
      "setup.sh",
      outside
    ])

    assert {_, 0} =
             cli(["start", "--attach", setup], env: [{"REALM_HOST_SENTINEL", "host only"}])

    Files.assert_reply(server, :read, "prepared.txt", %{}, %{content: "prepared by Realm setup\n"})

    assert observe.("prepared.txt") == {:ok, "prepared by Realm setup\n"}
    assert File.read!(outside) == "host only"

    preview = "realm-preview-" <> nonce
    register_cleanup(preview)
    port = loopback_port()
    url = "http://127.0.0.1:#{port}/"

    create!(
      preview,
      root,
      image,
      ["--env", "PORT=8080", "--publish", "127.0.0.1:#{port}:8080"],
      "/bin/sh",
      ["app.sh"]
    )

    assert {_, 0} = cli(["start", preview])

    assert preview_response(preview, url, System.monotonic_time(:millisecond) + 10_000) ==
             "PREPARED BY REALM SETUP\n"

    assert {_, 0} = cli(["stop", preview])
    assert {:error, _} = request(url)
  end

  defp assert_cached_image(image) do
    assert {output, 0} = cli(["image", "inspect", image])
    assert [_ | _] = JSON.decode!(output)
  end

  defp create!(id, root, image, flags, executable, args) do
    base = [
      "create",
      "--name",
      id,
      "--platform",
      "linux/arm64",
      "--cap-drop",
      "ALL",
      "--cpus",
      "1",
      "--memory",
      "256M",
      "--mount",
      "type=bind,source=#{root},target=/workspace",
      "--workdir",
      "/workspace",
      "--entrypoint",
      executable
    ]

    assert {output, 0} = cli(base ++ flags ++ [image | args])
    assert String.trim(output) == id
  end

  defp register_cleanup(id) do
    on_exit(fn ->
      cli(["delete", "--force", id])
      assert {_, status} = cli(["inspect", id])
      assert status != 0
    end)
  end

  defp loopback_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp preview_response(id, url, deadline) do
    case request(url) do
      {:ok, body} ->
        body

      {:error, reason} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {logs, _} = cli(["logs", id])
          flunk("preview did not become ready (curl #{reason})\n#{logs}")
        end

        Process.sleep(50)
        preview_response(id, url, deadline)
    end
  end

  defp request(url) do
    case System.cmd("curl", [
           "--noproxy",
           "127.0.0.1",
           "--silent",
           "--fail",
           "--max-time",
           "1",
           url
         ]) do
      {body, 0} -> {:ok, body}
      {_, status} -> {:error, status}
    end
  end

  defp cli(args, opts \\ []) do
    System.cmd("container", args, Keyword.put(opts, :stderr_to_stdout, true))
  end
end
