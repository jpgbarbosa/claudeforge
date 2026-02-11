#!/bin/bash
# setup-platform.sh — One-time setup for the swarm platform on VPS
# Run once on a fresh VPS to create the platform directory structure
# Usage: sudo ./setup-platform.sh

set -euo pipefail

PLATFORM_DIR="/opt/swarm-platform"

echo "Setting up swarm platform at $PLATFORM_DIR"

# Create directory structure
mkdir -p "$PLATFORM_DIR"/{projects,queue,logs,bin}

# Copy platform scripts
cp scripts/trigger.sh "$PLATFORM_DIR/trigger.sh"
cp scripts/register-project.sh "$PLATFORM_DIR/register-project.sh"
chmod +x "$PLATFORM_DIR"/*.sh

# Create a queue processor that checks for pending issues
cat > "$PLATFORM_DIR/process-queue.sh" << 'QUEUE_SCRIPT'
#!/bin/bash
# process-queue.sh — Checks queued issues and starts the next one when swarm is idle
# Run via cron every 5 minutes

PLATFORM_DIR="/opt/swarm-platform"

for queue_file in "$PLATFORM_DIR"/queue/*.queue; do
  [ -f "$queue_file" ] || continue
  [ -s "$queue_file" ] || continue  # skip empty

  PROJECT_NAME=$(basename "$queue_file" .queue)
  PROJECT_DIR="$PLATFORM_DIR/projects/$PROJECT_NAME"

  [ -d "$PROJECT_DIR" ] || continue

  cd "$PROJECT_DIR"

  # Check if swarm is idle
  STATUS=$(jq -r '.status' swarm-state.json 2>/dev/null || echo "idle")
  if [ "$STATUS" = "idle" ] || [ "$STATUS" = "completed" ]; then
    # Pop next issue from queue
    NEXT_ISSUE=$(head -1 "$queue_file")
    if [ -n "$NEXT_ISSUE" ]; then
      sed -i '1d' "$queue_file"  # Remove first line

      REPO=$(yq -r '.repo' .swarm/config.yaml)
      "$PLATFORM_DIR/trigger.sh" "$REPO" "$NEXT_ISSUE"
    fi
  fi
done
QUEUE_SCRIPT
chmod +x "$PLATFORM_DIR/process-queue.sh"

echo ""
echo "✅ Platform setup complete!"
echo ""
echo "Add to crontab (crontab -e):"
echo "  */5 * * * * $PLATFORM_DIR/process-queue.sh >> $PLATFORM_DIR/logs/queue.log 2>&1"
echo ""
echo "Prerequisites:"
echo "  - gh CLI installed and authenticated"
echo "  - claude (Claude Code CLI) installed and authenticated"
echo "  - yq and jq installed"
echo "  - Git SSH keys configured for GitHub access"
