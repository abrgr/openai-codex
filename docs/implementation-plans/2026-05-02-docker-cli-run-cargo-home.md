# Goal

Update `docker-cli-run.sh` so containerized tools get a usable Cargo home by default.

The runner should ensure `${HOME}/.cargo` exists on the host, mount it read-write at the same path in the container, and set `CARGO_HOME` to that path for the container process.

# Current Behavior

- `docker_cli_run` mounts a small set of standard host paths when they already exist: `.gitconfig`, `.ssh`, `.codex`, git credentials, and the Docker socket.
- User-requested directories can be mounted with `--add-dir` / `--add-dirs`.
- The runner sets `USER` and `HOME` in the container, then appends tool-specific environment variables.
- There is no default Cargo cache/config mount, and `CARGO_HOME` is not set.

# Intended Solution

## Public Interface

- No new user-facing flag is needed.
- Every `docker_cli_run` invocation gets a default Cargo home at `${HOME}/.cargo`.
- The host directory is created before `docker run` if it does not already exist.
- The directory is mounted as `${HOME}/.cargo:${HOME}/.cargo:rw`.
- The container receives `CARGO_HOME=${HOME}/.cargo`.

## Creation Contract

- Create `${HOME}/.cargo` from the wrapper process before building Docker arguments.
- Because the wrapper runs as the calling host user, a plain `mkdir -p "${HOME}/.cargo"` creates the directory as the current user under normal permissions and umask.
- If creation fails, fail before invoking Docker and print a clear error.

## Environment Contract

- Add `CARGO_HOME=${HOME}/.cargo` to the default environment alongside `USER` and `HOME`.
- Keep tool-specific `--env` entries appended after defaults so a tool wrapper can intentionally override `CARGO_HOME` if needed.
- The default mount remains `${HOME}/.cargo` even if a tool-specific override chooses a different `CARGO_HOME`; that preserves the requested default without coupling the shared runner to per-tool policy.

## Semantic Layering

- Keep this in the Docker integration layer, not in `alias`, because Cargo cache mounting is shared container runtime behavior.
- Keep argument parsing unchanged; default Cargo support should not interact with `--add-dir` / `--add-dirs`.
- Keep the mount construction simple and explicit with the other standard mounts.

# Implementation Sketch

1. Add a small helper such as `docker_cli_ensure_dir <path> <label>` or a focused inline block before standard volume mounts.
2. Ensure `${HOME}/.cargo` exists, failing with a clear message if `mkdir -p` fails.
3. Add `${HOME}/.cargo:${HOME}/.cargo:rw` to the standard `volume_args`.
4. Add `-e "CARGO_HOME=${HOME}/.cargo"` to the default `env_args` before tool-specific envs are appended.
5. Update comments only where they describe the runner-provided behavior.

# Tests

Use the existing `tests/docker-cli-run-test.sh` shell harness.

- Add a test where `${HOME}/.cargo` does not exist before the run.
- Assert the run succeeds.
- Assert the host `${HOME}/.cargo` directory was created.
- Assert Docker args include `${HOME}/.cargo:${HOME}/.cargo:rw`.
- Assert Docker args include `CARGO_HOME=${HOME}/.cargo`.
- Add or include a focused override check that a tool-provided `--env CARGO_HOME=/custom/cargo` is still present after defaults, preserving existing default-then-tool-specific env ordering.

# Open Questions

None. I will treat `~/.cargo` as `${HOME}/.cargo`, matching the runner's existing same-path host/container `HOME` contract.
