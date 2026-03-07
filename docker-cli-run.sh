#!/usr/bin/env bash
# Shared Docker CLI run logic for containerized dev tools.
#
# Usage:
#   source docker-cli-run.sh
#   docker_cli_run --image <name> --cmd <executable> [--cmd-arg <arg>]... [--env K=V]... [--mount host:container:mode]... -- [user-args...]
#
# Provides: --add-dir argument parsing, git root/worktree detection,
# standard volume mounts, user mapping, HOME/USER env vars.

docker_cli_run() {
  local image=""
  local -a cmd=()
  local -a tool_envs=()
  local -a tool_mounts=()
  local -a user_args=()

  # Parse docker_cli_run arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image)
        image="$2"; shift 2 ;;
      --cmd)
        cmd+=("$2"); shift 2 ;;
      --cmd-arg)
        cmd+=("$2"); shift 2 ;;
      --env)
        tool_envs+=("$2"); shift 2 ;;
      --mount)
        tool_mounts+=("$2"); shift 2 ;;
      --)
        shift; user_args=("$@"); break ;;
      *)
        echo "docker_cli_run: unknown option: $1" >&2; return 1 ;;
    esac
  done

  if [[ -z "$image" ]]; then
    echo "docker_cli_run: --image is required" >&2
    return 1
  fi
  if [[ ${#cmd[@]} -eq 0 ]]; then
    echo "docker_cli_run: --cmd is required" >&2
    return 1
  fi

  # Parse user args: extract --add-dir, pass through everything else
  local -a extra_mounts=()
  local -a pass_args=()

  for ((i=0; i<${#user_args[@]}; i++)); do
    if [[ "${user_args[$i]}" == "--add-dir" ]]; then
      if [[ -n "${user_args[$((i+1))]}" ]]; then
        extra_mounts+=("${user_args[$((i+1))]}")
        ((i++))
      else
        echo "Error: --add-dir requires a path argument" >&2
        return 1
      fi
    else
      pass_args+=("${user_args[$i]}")
    fi
  done

  # Find git root or fall back to cwd
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  local mount_path="${git_root:-$(pwd)}"
  local work_dir
  work_dir="$(pwd)"

  # If in a worktree, also mount the main repo root
  local git_common_dir
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [[ -n "$git_common_dir" && "$git_common_dir" != ".git" && "$git_common_dir" != "${mount_path}/.git" ]]; then
    local main_repo_root
    main_repo_root=$(cd "${mount_path}" && realpath "${git_common_dir}/..")
    extra_mounts+=("${main_repo_root}")
  fi

  # Standard volume mounts
  local -a volume_args=(
    -v "${mount_path}":"${mount_path}":rw
  )
  if [[ -f "${HOME}/.gitconfig" ]]; then
    volume_args+=(-v "${HOME}/.gitconfig:${HOME}/.gitconfig:ro")
  fi
  if [[ -d "${HOME}/.ssh" ]]; then
    volume_args+=(-v "${HOME}/.ssh:${HOME}/.ssh:ro")
  fi
  if [[ -S "/var/run/docker.sock" ]]; then
    volume_args+=(-v "/var/run/docker.sock:/var/run/docker.sock")
  fi

  # Git credentials (optional)
  if [[ -f "${HOME}/.git-credentials" ]]; then
    volume_args+=(-v "${HOME}/.git-credentials:${HOME}/.git-credentials:ro")
  fi

  # Tool-specific mounts
  for mnt in "${tool_mounts[@]}"; do
    volume_args+=(-v "$mnt")
  done

  # Extra user-requested mounts (--add-dir)
  for dir in "${extra_mounts[@]}"; do
    volume_args+=(-v "$dir":"$dir":rw)
  done

  # Tool-specific env vars
  local -a env_args=(-e "USER=${USER}" -e "HOME=${HOME}")
  for env in "${tool_envs[@]}"; do
    env_args+=(-e "$env")
  done

  # Add docker group if the socket is mounted
  local -a group_args=()
  local docker_gid
  docker_gid=$(getent group docker 2>/dev/null | cut -d: -f3)
  if [[ -n "$docker_gid" && -S "/var/run/docker.sock" ]]; then
    group_args=(--group-add "$docker_gid")
  fi

  docker run --rm -it \
    "${volume_args[@]}" \
    -w "${work_dir}" \
    "${env_args[@]}" \
    "${group_args[@]}" \
    --user "${UID}:$(id -g)" \
    "$image" "${cmd[@]}" "${pass_args[@]}"
}
