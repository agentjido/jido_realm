defmodule Jido.Realm.Conformance.ArtifactBrowser do
  @moduledoc false

  alias Jido.Realm.Artifacts

  @script Path.join(__DIR__, "review_artifact.mjs")

  def serve(store, id) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, packet: :http_bin])

    {:ok, port} = :inet.port(listener)
    access = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    ExUnit.Callbacks.start_supervised!({Task, fn -> accept(listener, store, id, access) end})

    "http://127.0.0.1:#{port}/#{access}/index.html"
  end

  def review(url) do
    chrome =
      System.get_env("JIDO_REALM_CHROME") || System.find_executable("chromium") ||
        System.find_executable("google-chrome") ||
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    System.cmd("node", [@script, chrome, url], stderr_to_stdout: true)
  end

  defp accept(listener, store, id, access) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        respond(socket, store, id, access)
        :gen_tcp.close(socket)
        accept(listener, store, id, access)

      {:error, :closed} ->
        :ok
    end
  end

  defp respond(socket, store, id, access) do
    result =
      with {:ok, {:http_request, :GET, {:abs_path, target}, _}} <- :gen_tcp.recv(socket, 0, 1_000),
           :ok <- consume_headers(socket),
           ["", ^access, path] <- String.split(target, "/", parts: 3) do
        Artifacts.read(store, :reviewer, id, path)
      end

    case result do
      {:ok, %{content: bytes, headers: headers}} ->
        headers = Enum.map(headers, fn {key, value} -> [key, ": ", value, "\r\n"] end)

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\n",
          headers,
          "Connection: close\r\n",
          "Content-Length: ",
          Integer.to_string(byte_size(bytes)),
          "\r\n\r\n",
          bytes
        ])

      _ ->
        :gen_tcp.send(
          socket,
          "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
        )
    end
  end

  defp consume_headers(socket) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, :http_eoh} -> :ok
      {:ok, {:http_header, _, _, _, _}} -> consume_headers(socket)
      _ -> :error
    end
  end
end
