#!/usr/bin/env bash
# Shared Docker CLI run logic for containerized dev tools.
#
# Usage:
#   source docker-cli-run.sh
#   docker_cli_run --image <name> --cmd <executable> [--cmd-arg <arg>]... [--env K=V]... [--mount host:container:mode]... -- [user-args...]
#
# Provides: --add-dir/--add-dirs argument parsing, explicit volume mounts,
# user mapping, HOME/USER env vars, and caller-pwd working-directory setup.

docker_cli_trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

docker_cli_normalize_mount_dir() {
  local raw_dir="$1"
  local base_dir="$2"
  local mount_dir

  mount_dir=$(docker_cli_trim_whitespace "$raw_dir")
  if [[ -z "$mount_dir" ]]; then
    echo "Error: mount directory entries must be non-empty" >&2
    return 1
  fi

  if [[ "$mount_dir" != /* ]]; then
    mount_dir="${base_dir}/${mount_dir}"
  fi

  if mount_dir=$(realpath -m "$mount_dir" 2>/dev/null); then
    printf '%s\n' "$mount_dir"
    return 0
  fi

  if mount_dir=$(realpath "$mount_dir" 2>/dev/null); then
    printf '%s\n' "$mount_dir"
    return 0
  fi

  printf '%s\n' "$mount_dir"
}

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

  local work_dir
  work_dir="$(pwd)"

  # Parse user args: extract wrapper-only mount flags, pass through everything else
  local -a extra_mounts=()
  local -a pass_args=()
  local i
  local raw_dir
  local normalized_dir
  local raw_dirs
  local -a raw_dir_entries=()
  local entry

  for ((i=0; i<${#user_args[@]}; i++)); do
    case "${user_args[$i]}" in
      --add-dir)
        if (( i + 1 >= ${#user_args[@]} )) || [[ -z "${user_args[$((i+1))]}" ]]; then
          echo "Error: --add-dir requires a path argument" >&2
          return 1
        fi
        raw_dir="${user_args[$((i+1))]}"
        normalized_dir=$(docker_cli_normalize_mount_dir "$raw_dir" "$work_dir") || return 1
        extra_mounts+=("$normalized_dir")
        ((i++))
        ;;
      --add-dirs)
        if (( i + 1 >= ${#user_args[@]} )) || [[ -z "${user_args[$((i+1))]}" ]]; then
          echo "Error: --add-dirs requires a comma-separated path list" >&2
          return 1
        fi
        raw_dirs="${user_args[$((i+1))]}"
        if [[ "$raw_dirs" =~ ^[[:space:]]*, ]] || [[ "$raw_dirs" =~ ,[[:space:]]*$ ]] || [[ "$raw_dirs" =~ ,[[:space:]]*, ]]; then
          echo "Error: --add-dirs entries must be non-empty" >&2
          return 1
        fi
        IFS=',' read -r -a raw_dir_entries <<< "$raw_dirs"
        for entry in "${raw_dir_entries[@]}"; do
          normalized_dir=$(docker_cli_normalize_mount_dir "$entry" "$work_dir") || return 1
          extra_mounts+=("$normalized_dir")
        done
        ((i++))
        ;;
      *)
        pass_args+=("${user_args[$i]}")
        ;;
    esac
  done

  # Standard volume mounts
  local -a volume_args=()
  if [[ -f "${HOME}/.gitconfig" ]]; then
    volume_args+=(-v "${HOME}/.gitconfig:${HOME}/.gitconfig:ro")
  fi
  if [[ -d "${HOME}/.ssh" ]]; then
    volume_args+=(-v "${HOME}/.ssh:${HOME}/.ssh:ro")
  fi
  if [[ -d "${HOME}/.codex" ]]; then
    volume_args+=(-v "${HOME}/.codex:${HOME}/.codex:rw")
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

  # Extra user-requested mounts (--add-dir/--add-dirs)
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
    --tmpfs "${HOME}:exec,uid=${UID},gid=$(id -g)" \
    "${volume_args[@]}" \
    -w "${work_dir}" \
    "${env_args[@]}" \
    "${group_args[@]}" \
    --user "${UID}:$(id -g)" \
    "$image" "${cmd[@]}" "${pass_args[@]}"
}
