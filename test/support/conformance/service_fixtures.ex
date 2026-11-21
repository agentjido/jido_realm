defmodule Jido.Realm.Conformance.ServiceFixtures do
  @moduledoc false

  @typescript %{
    "render.ts" => """
    export function render(name: string): string {
      return `<h1>Hello, ${name}!</h1>`;
    }
    """,
    "verify.ts" => """
    import assert from "node:assert/strict";
    import { render } from "./render.ts";
    assert.equal(render("Realm"), "<h1>Hello, Realm!</h1>");
    console.log("TypeScript check passed");
    """,
    "server.ts" => """
    import { createServer } from "node:http";
    import { render } from "./render.ts";
    createServer((_req, res) => {
      res.writeHead(200, { "Content-Type": "text/html" });
      res.end(render("Realm"));
    }).listen(Number(process.env.PORT), "0.0.0.0");
    """
  }

  @phoenix Path.expand(
             "../../integration/09_model_driven_files/apple_edit_fixture",
             __DIR__
           )

  def typescript, do: @typescript

  def phoenix do
    for file <- Path.wildcard(Path.join(@phoenix, "**/*.seed")),
        path = file |> Path.relative_to(@phoenix) |> String.trim_trailing(".seed"),
        not String.starts_with?(path, "acceptance/"),
        into: %{} do
      {path, File.read!(file)}
    end
  end
end
