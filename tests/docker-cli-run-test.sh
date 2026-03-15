#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIG_PATH="$PATH"
TEST_ROOT="$(mktemp -d)"

trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  if [[ -n "${RUN_STDERR_FILE:-}" && -f "${RUN_STDERR_FILE}" ]]; then
    echo "--- stderr ---" >&2
    cat "${RUN_STDERR_FILE}" >&2
  fi
  if [[ -n "${RUN_DOCKER_ARGS_FILE:-}" && -f "${RUN_DOCKER_ARGS_FILE}" ]]; then
    echo "--- docker args ---" >&2
    cat "${RUN_DOCKER_ARGS_FILE}" >&2
  fi
  exit 1
}

setup_case() {
  CASE_DIR="$(mktemp -d "${TEST_ROOT}/case.XXXXXX")"
  TEST_HOME="${CASE_DIR}/home"
  FAKE_BIN="${CASE_DIR}/bin"
  RUN_STDOUT_FILE="${CASE_DIR}/stdout"
  RUN_STDERR_FILE="${CASE_DIR}/stderr"
  RUN_DOCKER_ARGS_FILE="${CASE_DIR}/docker.args"

  mkdir -p "$TEST_HOME" "$FAKE_BIN"

  cat > "${FAKE_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_DOCKER_ARGS_FILE:?}"
EOF
  chmod +x "${FAKE_BIN}/docker"
}

run_docker_cli_run() {
  local cwd="$1"
  shift

  if (
    export HOME="$TEST_HOME"
    export USER="tester"
    export PATH="${FAKE_BIN}:${ORIG_PATH}"
    export FAKE_DOCKER_ARGS_FILE="$RUN_DOCKER_ARGS_FILE"
    cd "$cwd"
    source "${REPO_ROOT}/docker-cli-run.sh"
    docker_cli_run "$@"
  ) >"${RUN_STDOUT_FILE}" 2>"${RUN_STDERR_FILE}"; then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
}

assert_status() {
  local expected="$1"
  if [[ "${RUN_STATUS}" -ne "${expected}" ]]; then
    fail "expected exit status ${expected}, got ${RUN_STATUS}"
  fi
}

assert_args_contains() {
  local expected="$1"
  if ! grep -Fx -- "$expected" "${RUN_DOCKER_ARGS_FILE}" >/dev/null; then
    fail "expected docker args to contain: ${expected}"
  fi
}

assert_args_not_contains() {
  local unexpected="$1"
  if grep -Fx -- "$unexpected" "${RUN_DOCKER_ARGS_FILE}" >/dev/null; then
    fail "did not expect docker args to contain: ${unexpected}"
  fi
}

assert_stderr_contains() {
  local expected="$1"
  if ! grep -F -- "$expected" "${RUN_STDERR_FILE}" >/dev/null; then
    fail "expected stderr to contain: ${expected}"
  fi
}

test_add_dirs_csv_mounts_and_strips_flag() {
  setup_case

  local workspace="${CASE_DIR}/workspace"
  mkdir -p "${workspace}/sub/a" "${workspace}/b"

  run_docker_cli_run "${workspace}/sub" \
    --image test-image \
    --cmd codex \
    -- --add-dirs "./a, ../b" prompt

  assert_status 0
  assert_args_contains "${workspace}/sub/a:${workspace}/sub/a:rw"
  assert_args_contains "${workspace}/b:${workspace}/b:rw"
  assert_args_contains "-w"
  assert_args_contains "${workspace}/sub"
  assert_args_contains "prompt"
  assert_args_not_contains "--add-dirs"
}

test_legacy_add_dir_still_works() {
  setup_case

  local workspace="${CASE_DIR}/workspace"
  mkdir -p "${workspace}/sub" "${workspace}/shared"

  run_docker_cli_run "${workspace}/sub" \
    --image test-image \
    --cmd codex \
    -- --add-dir "../shared" prompt

  assert_status 0
  assert_args_contains "${workspace}/shared:${workspace}/shared:rw"
  assert_args_not_contains "--add-dir"
}

test_missing_add_dirs_value_fails() {
  setup_case

  local workspace="${CASE_DIR}/workspace"
  mkdir -p "${workspace}"

  run_docker_cli_run "${workspace}" \
    --image test-image \
    --cmd codex \
    -- --add-dirs

  assert_status 1
  assert_stderr_contains "Error: --add-dirs requires a comma-separated path list"
}

test_empty_add_dirs_entry_fails() {
  setup_case

  local workspace="${CASE_DIR}/workspace"
  mkdir -p "${workspace}/a" "${workspace}/b"

  run_docker_cli_run "${workspace}" \
    --image test-image \
    --cmd codex \
    -- --add-dirs "./a,,./b"

  assert_status 1
  assert_stderr_contains "Error: --add-dirs entries must be non-empty"
}

test_pwd_is_workdir_without_implicit_repo_mounts() {
  setup_case

  command -v git >/dev/null || fail "git is required for this test"

  local repo="${CASE_DIR}/repo"
  mkdir -p "${repo}/subdir"
  git init -q "${repo}"

  run_docker_cli_run "${repo}/subdir" \
    --image test-image \
    --cmd codex \
    -- prompt

  assert_status 0
  assert_args_contains "-w"
  assert_args_contains "${repo}/subdir"
  assert_args_not_contains "${repo}:${repo}:rw"
  assert_args_not_contains "${repo}/subdir:${repo}/subdir:rw"
}

run_test() {
  local test_name="$1"
  "$test_name"
  echo "ok - ${test_name}"
}

run_test test_add_dirs_csv_mounts_and_strips_flag
run_test test_legacy_add_dir_still_works
run_test test_missing_add_dirs_value_fails
run_test test_empty_add_dirs_entry_fails
run_test test_pwd_is_workdir_without_implicit_repo_mounts

echo "PASS"
