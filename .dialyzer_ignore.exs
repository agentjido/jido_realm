[
  # These actions accept atoms in BEAM calls. Jido's generated JSON contract
  # raises for these schemas, while validation and execution remain available.
  ~r{^deps/jido/lib/jido/instruction/compiler\.ex:\d+:no_return Function authoring_contract/0 has no local return\.},
  ~r{^deps/jido/lib/jido/instruction/compiler\.ex:\d+:call The function call contract! will not succeed\.},
  ~r{^lib/jido_realm/(file_action|run_action|workspace_action)\.ex:\d+:invalid_contract Invalid type specification for function authoring_contract\.}
]
