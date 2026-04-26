# Goal

Make `./build.sh` succeed again by pinning the Gitpod base image to a specific recent timestamp and removing the failing Ubuntu PPA from the image build path without changing the public build interface.

# Current Behavior

- [Dockerfile](/home/adam/code/codex/Dockerfile:1) starts from `gitpod/workspace-full:latest`.
- The base image currently contains an `ondrej/nginx` apt source for Ubuntu `jammy`.
- The build runs a plain `apt-get update`, which fails because that PPA no longer publishes a valid `Release` file for `jammy`.
- As a result, the build never reaches package installation or the Codex CLI install step.
- `latest` is a moving tag, so even if it worked again later the build would remain non-reproducible.

# Intended Solution

## Public interface

- Keep `./build.sh` unchanged.
- Keep `Dockerfile` accepting the same `CODEX_VERSION` build arg.
- Keep the installed package set unchanged: `jq`, `less`, and `tree`.
- Replace `gitpod/workspace-full:latest` with the current timestamped tag `gitpod/workspace-full:2026-02-12-23-06-03`.

## Build contract

- Before `apt-get update`, explicitly remove the broken `ondrej/nginx` source if it exists in the inherited base image.
- Pin the base image tag so the repository depends on a stable, reviewable Gitpod image version instead of a moving target.
- Treat this as image hygiene in the integration layer (`Dockerfile`), not as application logic.
- Do not suppress apt failures globally and do not enable insecure repository behavior; the build should still fail for unexpected apt issues.

## Semantic layering

- `build.sh` remains a thin entrypoint that resolves the desired Codex version and invokes `docker build`.
- `Dockerfile` remains responsible for normalizing the inherited OS package manager state before installing required packages.
- The base-image pin and source-removal step should both be small and explicit so future image changes are deliberate and reviewable.

# Implementation Sketch

1. Replace the `latest` base image reference in `Dockerfile` with `gitpod/workspace-full:2026-02-12-23-06-03`.
2. Update the root package-install layer in `Dockerfile`.
3. Add a bounded shell step that deletes any apt source list entries referencing `ppa.launchpadcontent.net/ondrej/nginx` before `apt-get update`.
4. Keep the existing package install and cache cleanup flow intact.
5. Re-run `./build.sh` to verify the image now builds successfully.

# Tests

- Primary verification: `./build.sh` completes successfully end-to-end.
- Secondary verification: confirm the resulting image still includes the expected utilities and still installs `@openai/codex` at the requested version.
- Reproducibility verification: confirm the resulting build uses the pinned Gitpod tag rather than `latest`.

# Notes

- I am intentionally keeping the same image family because `workspace-full` is still Gitpod’s maintained “all the dev tools” image; the change is to make that dependency explicit and reproducible.
- The apt-source cleanup is still necessary because pinning alone is unlikely to fix this specific failure if the pinned image also carries the broken PPA.
