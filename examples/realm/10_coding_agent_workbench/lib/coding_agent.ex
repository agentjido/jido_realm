defmodule RealmWorkbench.CodingAgent do
  use Jido.Agent, name: "realm_workbench_coder", plugins: [Jido.Realm.Plugin]

  realms do
    realm(:work, profile: :program)
  end

  routes do
    signal_source("/workbench")
    route("workbench.build", RealmWorkbench.BuildAction)
  end
end

defmodule RealmWorkbench.BuildAction do
  alias Jido.{Joi, Realm}
  alias RealmWorkbench.Runs

  use Jido.Action,
    name: "build_in_realm",
    description: "Uses the local coding model to build and verify a small app in Realm.",
    schema: Joi.object(%{id: Joi.string(), provider: Joi.string(), recipe: Joi.string()})

  @files %{"phoenix" => ["mix.exs", "lib/hello.ex"], "typescript" => ["server.ts"]}
  @agent """
  You are a coding agent working in an empty Jido Realm. Create a real runnable project.
  Your only tool is submitting changes as one JSON object. Return compact JSON with
  {"summary":"short summary","files":[{"path":"allowed path","content":"complete source text"}]}.
  The host writes each file and runs the app. If it fails, you receive the build or HTTP error
  and the current files. Fix the files that need changes. Use only the listed paths.
  Do not include markdown fences or another JSON wrapper. Keep source concise.
  Perform no external work.
  """

  @impl true
  def run(job, context) do
    with {:ok, _} <- Realm.open(context, :work),
         :ok <- prepare_dirs(context, job) do
      Runs.log(job.id, "Opened Jido Realm on #{job.provider}.")

      result =
        try do
          build(job, context, %{}, nil, 1)
        after
          Realm.close(context, :work)
        end

      case result do
        {:ok, data} ->
          with {:ok, reply} <- Jido.Agent.build_signal(context, "workbench.result", data) do
            {:ok, context.agent_state, [Jido.Agent.Directive.reply(reply)]}
          end

        {:error, reason} ->
          failure(reason)
      end
    else
      {:error, reason} -> failure(reason)
    end
  end

  defp prepare_dirs(context, %{recipe: "phoenix"}) do
    case Realm.file(context, :work, :mkdir, "lib") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare_dirs(_, _), do: :ok

  defp build(job, context, files, previous_error, attempt) when attempt <= 4 do
    Runs.log(job.id, "Inkling is preparing source files (attempt #{attempt}).")

    with {:ok, response} <- generate(job, files, previous_error),
         :ok <- validate_files(job, response, files),
         :ok <- write_files(context, response["files"]),
         {:ok, current} <- read_files(context, @files[job.recipe]) do
      Runs.log(job.id, response["summary"])
      Runs.log(job.id, "Starting #{job.recipe} on #{job.provider} through Realm.")

      case Realm.invoke(context, :work, :start_preview, %{}) do
        {:ok, preview} ->
          Runs.log(job.id, "HTTP 200 confirmed. Hello, world! is visible.")
          {:ok, Map.put(preview, :files, current)}

        {:error, reason} ->
          Runs.log(job.id, "Preview failed. Sending the build output to Inkling.")
          build(job, context, current, reason, attempt + 1)
      end
    else
      {:error, reason} ->
        Runs.log(job.id, "Attempt failed: " <> describe(reason))
        build(job, context, files, reason, attempt + 1)
    end
  end

  defp build(_job, _context, _files, error, _attempt), do: {:error, error}

  defp generate(job, files, previous_error) do
    message = """
    Build a #{job.recipe} app in #{job.provider}. Write #{Enum.join(@files[job.recipe], " and ")}.
    #{requirements(job.recipe)}
    The browser must show the exact heading Hello, world! at GET /.
    """

    message =
      if previous_error do
        message <>
          "\nCurrent source: " <>
          JSON.encode!(files) <>
          "\nVerify error: " <> String.slice(describe(previous_error), -2_400, 2_400)
      else
        message
      end

    headers =
      case System.get_env("WORKBENCH_LLM_KEY") do
        nil -> []
        key -> [{"authorization", "Bearer " <> key}]
      end

    request = %{
      model: Runs.model(),
      messages: [%{role: "system", content: @agent}, %{role: "user", content: message}],
      temperature: 0.1,
      max_tokens: 2_800,
      response_format: %{type: "json_object"},
      reasoning_effort: "minimal",
      chat_template_kwargs: %{reasoning_effort: "minimal"}
    }

    case Req.post(String.trim_trailing(Runs.base_url(), "/") <> "/chat/completions",
           json: request,
           headers: headers,
           retry: false,
           receive_timeout: 360_000
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}}
      when is_binary(content) ->
        case JSON.decode(content) do
          {:ok, %{} = reply} -> {:ok, reply}
          _ -> {:error, "The model response was not a complete JSON object."}
        end

      {:ok, %{status: status, body: %{"error" => %{"message" => message}}}} ->
        {:error, "Model endpoint returned HTTP #{status}: #{message}"}

      {:ok, %{status: status}} ->
        {:error, "Model endpoint returned HTTP #{status}."}

      {:error, _} ->
        {:error, "Model endpoint did not respond."}
    end
  end

  defp requirements("phoenix"),
    do: """
    Create a true Mix OTP project named :realm_hello. Pin Phoenix 1.8.17 and Bandit 1.15.0.
    Use Phoenix.Router and `use Phoenix.Endpoint, otp_app: :realm_hello`.
    Start the endpoint under the application supervisor.
    Define all modules in lib/hello.ex. Define the controller before the router and the
    router before the endpoint. Use Plug.Conn.send_resp with text/html.
    Inside RealmHello.Application.start/2, configure RealmHello.Endpoint via
    Application.put_env immediately before calling Supervisor.start_link. Put the port
    lookup and all Application.put_env calls inside start/2 so they run at startup.
    Use adapter Bandit.PhoenixAdapter, server: true, a valid secret_key_base and
    http: [ip: ip, port: port]. Use `{:ok, ip} = :inet.parse_address(String.to_charlist(System.fetch_env!("BIND_IP")))`
    and `port = String.to_integer(System.fetch_env!("PORT"))`. Pass only the IP tuple as `ip`.
    Configure the `:phoenix` application's `:json_library` to JSON if needed.
    Route a module plug via forward "/" or a Phoenix controller via get "/".
    If the route uses a fully qualified controller name, use scope "/" without a module prefix.
    Avoid a database, JavaScript dependencies, assets, and generated HTML view templates.
    """

  defp requirements("typescript"),
    do: """
    Use real TypeScript with erasable types and node:http. Node runs:
      node --experimental-strip-types server.ts
    Use import statements and the PORT and BIND_IP environment variables.
    Send text/html with a small, styled Jido Realm landing page. Include a page title and one
    sentence about agent workspaces. Return exactly one file named server.ts. Node detects the
    module format from the source. Use no package.json, tsconfig.json, install, or build tool.
    """

  defp validate_files(job, %{"files" => patch, "summary" => summary}, files)
       when is_list(patch) and patch != [] and is_binary(summary) do
    allowed = @files[job.recipe]

    with true <- Enum.all?(patch, &valid_file?(&1, allowed)),
         paths <- Enum.map(patch, & &1["path"]),
         true <- Enum.uniq(paths) == paths,
         [] <- allowed -- Enum.uniq(Map.keys(files) ++ paths) do
      :ok
    else
      _ ->
        supplied = Enum.map(patch, fn file -> if is_map(file), do: file["path"] end)

        {:error,
         "Expected paths from #{inspect(allowed)}. Received #{inspect(supplied)}. Include complete source text."}
    end
  end

  defp validate_files(_, _, _), do: {:error, "Return summary and a nonempty files array."}

  defp valid_file?(%{"path" => path, "content" => bytes}, allowed),
    do: path in allowed and is_binary(bytes) and byte_size(bytes) in 1..24_000

  defp valid_file?(_, _), do: false

  defp write_files(context, files) do
    Enum.reduce_while(files, :ok, fn %{"path" => path, "content" => bytes}, :ok ->
      result =
        case Realm.file(context, :work, :create, path, bytes) do
          {:error, :already_exists} -> Realm.file(context, :work, :edit, path, bytes)
          result -> result
        end

      case result do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp read_files(context, paths) do
    Enum.reduce_while(paths, {:ok, %{}}, fn path, {:ok, files} ->
      case Realm.file(context, :work, :read, path) do
        {:ok, %{content: content}} -> {:cont, {:ok, Map.put(files, path, content)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp failure(reason) do
    {:error,
     Jido.Error.execution_error("Coding build failed", details: %{reason: describe(reason)})}
  end

  defp describe(value) when is_binary(value), do: value
  defp describe(value), do: inspect(value)
end
