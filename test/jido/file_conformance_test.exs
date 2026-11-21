defmodule Jido.Realm.FileConformanceTest do
  alias Jido.Realm.Conformance.{Files, LocalFixture, MemoryFixture}

  use Files, bindings: [local: LocalFixture, memory: MemoryFixture]
end
