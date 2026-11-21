defmodule RealmWorkbench do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Jido, name: RealmWorkbench.Jido},
      {Task.Supervisor, name: RealmWorkbench.Tasks},
      RealmWorkbench.Runs,
      RealmWorkbench.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RealmWorkbench.Supervisor)
  end
end

defmodule RealmWorkbench.Page do
  use Phoenix.Controller, formats: [:html, :json]
  alias RealmWorkbench.Runs

  def index(conn, _params) do
    conn
    |> put_resp_header("content-security-policy", "default-src 'self'; frame-ancestors 'none'")
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:realm_workbench, "priv/static/index.html"))
  end

  def runs(conn, _params), do: json(conn, %{model: Runs.model(), runs: Runs.list()})

  def start(conn, %{"provider" => provider, "recipe" => recipe}) do
    if local_request?(conn) do
      case Runs.start(provider, recipe) do
        {:ok, id} -> conn |> put_status(:accepted) |> json(%{id: id})
        {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
      end
    else
      conn |> put_status(:forbidden) |> json(%{error: "Open the workbench on localhost."})
    end
  end

  def start(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "Select a build."})

  defp local_request?(conn) do
    conn.host in ["localhost", "127.0.0.1"] and
      get_req_header(conn, "origin") in [
        [],
        ["http://localhost:#{conn.port}"],
        ["http://127.0.0.1:#{conn.port}"]
      ]
  end
end

defmodule RealmWorkbench.Router do
  use Phoenix.Router

  get("/", RealmWorkbench.Page, :index)
  get("/api/runs", RealmWorkbench.Page, :runs)
  post("/api/runs", RealmWorkbench.Page, :start)
end

defmodule RealmWorkbench.Endpoint do
  use Phoenix.Endpoint, otp_app: :realm_workbench

  plug(Plug.Static, at: "/", from: :realm_workbench, only: ~w(workbench.js workbench.css))
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: JSON)
  plug(RealmWorkbench.Router)
end
