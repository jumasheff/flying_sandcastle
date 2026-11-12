#!/usr/bin/env bash
# One factory run: refresh the project clone, rebuild the sandbox image if
# needed, then plan → implement → review → open PRs.
# Started by factory.service (systemd timer). Run by hand: sudo systemctl start factory
set -euo pipefail

FACTORY_DIR="${FACTORY_DIR:-/opt/factory}"
CONFIG_DIR="${CONFIG_DIR:-/etc/factory}"
WORK_DIR="${WORK_DIR:-/var/lib/factory}"
PROJECT_DIR="$WORK_DIR/project"

exec 9>"$WORK_DIR/run.lock"
if ! flock -n 9; then
  echo "Another run is still active. Skipping."
  exit 0
fi

set -a
# shellcheck disable=SC1091
source "$CONFIG_DIR/factory.env"
# shellcheck disable=SC1091
source "$CONFIG_DIR/secrets.env"
set +a
: "${TARGET_REPO:?set TARGET_REPO in $CONFIG_DIR/factory.env}"
: "${CLAUDE_CODE_OAUTH_TOKEN:?set CLAUDE_CODE_OAUTH_TOKEN in $CONFIG_DIR/secrets.env}"
: "${GH_TOKEN:?set GH_TOKEN in $CONFIG_DIR/secrets.env}"
export GH_REPO="$TARGET_REPO" GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

# git over HTTPS uses GH_TOKEN through gh.
gh auth setup-git >/dev/null

# --- Project clone ---------------------------------------------------------
if [ ! -d "$PROJECT_DIR/.git" ]; then
  git clone "https://github.com/$TARGET_REPO.git" "$PROJECT_DIR"
fi
cd "$PROJECT_DIR"
if [ "$(git remote get-url origin)" != "https://github.com/$TARGET_REPO.git" ]; then
  echo "Project clone is for another repo. Remove $PROJECT_DIR to switch projects." >&2
  exit 1
fi
git config user.name "$GIT_AUTHOR_NAME"
git config user.email "$GIT_AUTHOR_EMAIL"
git fetch --prune origin
git checkout -q -B "$BASE_BRANCH" "origin/$BASE_BRANCH"
git reset -q --hard "origin/$BASE_BRANCH"
git clean -qfd

# Sandcastle reads .sandcastle/.env from the repo and keeps its worktrees and
# logs in .sandcastle/. None of it goes into the project's git history.
mkdir -p .sandcastle
grep -qxF ".sandcastle/" .git/info/exclude || echo ".sandcastle/" >> .git/info/exclude
install -m 600 "$CONFIG_DIR/secrets.env" .sandcastle/.env

# Delete local agent branches whose PR was merged or closed (gone on GitHub).
for b in $(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/sandcastle/ | awk '$2=="[gone]"{print $1}'); do
  git branch -D "$b" || true
done

# --- Labels (idempotent) ----------------------------------------------------
gh label create "$READY_LABEL" --color 0E8A16 --description "Ready for the Sandcastle factory" --force >/dev/null
gh label create "$REVIEW_LABEL" --color FBCA04 --description "Sandcastle opened a PR" --force >/dev/null
gh label create "$HUMAN_LABEL" --color D93F0B --description "Sandcastle is stuck, needs a human" --force >/dev/null
gh label create "${IDEA_LABEL:-idea}" --color C5DEF5 --description "New idea, waiting for approval" --force >/dev/null

# Skip the agents (and Claude usage) when there is nothing to do.
ready=$(gh issue list --state open --label "$READY_LABEL" --limit 1 --json number --jq length)
if [ "$ready" = "0" ]; then
  echo "No issues labelled '$READY_LABEL'."
  exit 0
fi

# --- Sandbox image -----------------------------------------------------------
# Rebuild when the Dockerfile changes, and once a week for a fresh Claude Code.
IMAGE_NAME="${IMAGE_NAME:-sandcastle:factory}"
export IMAGE_NAME
stamp="$(sha256sum "$FACTORY_DIR/sandcastle/Dockerfile" | cut -c1-12)-$(date +%G%V)"
if [ "$(cat "$WORK_DIR/image.stamp" 2>/dev/null)" != "$stamp" ] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Building $IMAGE_NAME ..."
  docker build --pull -t "$IMAGE_NAME" \
    --build-arg AGENT_UID="$(id -u)" --build-arg AGENT_GID="$(id -g)" \
    "$FACTORY_DIR/sandcastle"
  echo "$stamp" > "$WORK_DIR/image.stamp"
  docker image prune -f >/dev/null
fi

# --- Go ------------------------------------------------------------------------
exec "$FACTORY_DIR/node_modules/.bin/tsx" "$FACTORY_DIR/sandcastle/main.mts"
