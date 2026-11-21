#!/usr/bin/env bash
set -euo pipefail

runs=${1:-5}
workers=${2:-2}

if [[ $# -gt 2 || ! $runs =~ ^([1-9]|[1-4][0-9]|50)$ || ! $workers =~ ^([1-9]|1[0-6])$ ]]; then
  echo "Usage: $0 [trials per backend, 1-50] [concurrent trials, 1-16]" >&2
  exit 2
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export JIDO_REALM_PRESSURE_RUNS=$runs

printf 'Running %s trials per backend on Local and Memory with up to %s concurrent trials.\n' "$runs" "$workers"
exec mix test test/integration/09_model_driven_files/file_agent_test.exs --only lmstudio --max-cases "$workers"
