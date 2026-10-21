# Shared helpers; sourced by the other scripts, not run directly.

if [[ ! -f .env ]]; then
  echo ".env not found. Create it: cp .env.example .env" >&2
  exit 1
fi

# Prints the value of KEY from .env (last assignment wins), without sourcing the file.
env_get() {
  local v
  v=$(sed -n "s/^$1=//p" .env | tail -n1)
  v=${v%"${v##*[![:space:]]}"}; v=${v#\"}; v=${v%\"}
  printf '%s' "$v"
}
