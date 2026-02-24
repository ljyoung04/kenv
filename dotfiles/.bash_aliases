alias l='ls -alt'
alias rp='realpath'
# OSC 52: copy stdin to terminal clipboard (works through SSH hops)
clip() {
  local data
  data=$(cat)
  local encoded
  encoded=$(printf '%s' "$data" | base64 | tr -d '\n')
  printf '\e]52;c;%s\a' "$encoded"
}

vs() {
  local target="${1:-.}"

  find_vscode_socket() {
    lsof | rg "$USER" | rg vscode-ipc | awk '{print $(NF-1)}' | head -n 1
  }

  if [ -n "$VSCODE_IPC_HOOK_CLI" ]; then
    code "$target"
    unset VSCODE_IPC_HOOK_CLI
    export VSCODE_IPC_HOOK_CLI=$(find_vscode_socket)
  else
    export VSCODE_IPC_HOOK_CLI=$(find_vscode_socket)
    code "$target"
  fi
}

watcher() {
  if [ $# -lt 2 ]; then
    echo "Usage: watcher <filename> <command...>"
    return 1
  fi

  local file="$1"
  shift
  local cmd="$*"

  if [ ! -f "$file" ]; then
    echo "Error: File '$file' does not exist."
    return 1
  fi

  if ! command -v inotifywait &>/dev/null; then
    echo "Error: inotifywait not found. please install inotify-tools."
    return 1
  fi

  echo "Watching '$file'... Press [Ctrl+C] to stop."

  while :; do
    inotifywait -e modify "$file" >/dev/null 2>&1
    echo "[$(date '+%H:%M:%S')] '$file' modified. Running: $cmd"
    eval "$cmd"
  done
}
