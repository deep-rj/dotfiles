# Paths under $HOME kept on the /workspace network volume and symlinked back,
# since everything else is wiped when the pod is recreated.
PERSIST_DIR=/workspace/.home
PERSIST_PATHS=(
  .claude/
  .claude.json
  .git-credentials
)

INSTALL_CLAUDE=true
