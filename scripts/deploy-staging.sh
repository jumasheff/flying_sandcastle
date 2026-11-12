#!/usr/bin/env bash
# Deploy the checked-out BASE_BRANCH to the staging Fly app when it changed
# since the last successful deploy:
#   1. apply new Supabase migrations to the staging database;
#   2. `fly deploy` with the staging app name and staging Supabase values.
# Called by run.sh from the project clone, with the factory env loaded.
# Run by hand (as the factory user): FORCE=1 ./deploy-staging.sh
set -euo pipefail

: "${STAGING_APP:?}" "${STAGING_SUPABASE_URL:?}" "${STAGING_SUPABASE_PUBLISHABLE_KEY:?}"
: "${FLY_API_TOKEN:?set FLY_API_TOKEN in host-secrets.env}"
STATE="$WORK_DIR/staging.deployed"
CONFIG=fly.staging.toml # inside the clone: Fly uses the config's folder as build context

sha=$(git rev-parse HEAD)
last=$(cat "$STATE" 2>/dev/null || true)
if [ "$sha" = "$last" ] && [ -z "${FORCE:-}" ]; then
  echo "Staging is up to date ($sha)."
  exit 0
fi
echo "Deploying $sha to $STAGING_APP ..."

# --- 1. Database migrations -------------------------------------------------------
# Applied before the new code goes live, like production (DEPLOY.md).
if [ -d supabase/migrations ] && { [ -z "$last" ] || ! git diff --quiet "$last" "$sha" -- supabase/migrations; }; then
  : "${STAGING_DB_URL:?set STAGING_DB_URL in host-secrets.env}"
  echo "Applying migrations to the staging database ..."
  npx -y supabase@3 db push --remote="$STAGING_DB_URL" --skip-vault --yes
fi

# --- 2. Fly config for staging --------------------------------------------------
# Same as fly.toml, with the staging app, the staging Supabase project and
# no always-on machine (staging may sleep; the first request wakes it).
grep -qxF "$CONFIG" .git/info/exclude || echo "$CONFIG" >> .git/info/exclude
sed -E \
  -e "s|^app = .*|app = \"$STAGING_APP\"|" \
  -e "s|^( *NEXT_PUBLIC_SUPABASE_URL = ).*|\1\"$STAGING_SUPABASE_URL\"|" \
  -e "s|^( *NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = ).*|\1\"$STAGING_SUPABASE_PUBLISHABLE_KEY\"|" \
  -e "s|^( *min_machines_running = ).*|\10|" \
  fly.toml > "$CONFIG"

# Refuse to deploy if fly.toml changed shape and a value was not replaced:
# a staging build must never point at the production database.
for want in "app = \"$STAGING_APP\"" "\"$STAGING_SUPABASE_URL\"" "\"$STAGING_SUPABASE_PUBLISHABLE_KEY\""; do
  if ! grep -qF "$want" "$CONFIG"; then
    echo "fly.toml format changed: could not set $want in $CONFIG. Not deploying." >&2
    exit 1
  fi
done

# --- 3. Deploy -------------------------------------------------------------------
# --remote-only: the image is built on Fly's builder, not on this server.
flyctl deploy --config "$CONFIG" --app "$STAGING_APP" --remote-only --ha=false \
  --build-arg NEXT_PUBLIC_SUPABASE_URL="$STAGING_SUPABASE_URL" \
  --build-arg NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="$STAGING_SUPABASE_PUBLISHABLE_KEY"

echo "$sha" > "$STATE"
echo "Staging: https://$STAGING_APP.fly.dev ($sha)"
