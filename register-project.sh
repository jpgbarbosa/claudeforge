#!/bin/bash
# register-project.sh — Register a new project with the swarm platform on VPS
# Usage: ./register-project.sh my-project git@github.com:org/my-project.git
# Lives on VPS at /opt/swarm-platform/register-project.sh

set -euo pipefail

PROJECT_NAME="${1:?Usage: ./register-project.sh project-name git-url}"
GIT_URL="${2:?Usage: ./register-project.sh project-name git-url}"
PLATFORM_DIR="/opt/swarm-platform"
PROJECTS_DIR="$PLATFORM_DIR/projects"
QUEUE_DIR="$PLATFORM_DIR/queue"
LOGS_DIR="$PLATFORM_DIR/logs"

# Ensure platform directories exist
mkdir -p "$PROJECTS_DIR" "$QUEUE_DIR" "$LOGS_DIR"

# Check if already registered
if [ -d "$PROJECTS_DIR/$PROJECT_NAME" ]; then
  echo "Project $PROJECT_NAME already registered at $PROJECTS_DIR/$PROJECT_NAME"
  echo "To re-register, remove the directory first."
  exit 1
fi

echo "Registering project: $PROJECT_NAME"
echo "  Git URL: $GIT_URL"

# Clone the repo
git clone "$GIT_URL" "$PROJECTS_DIR/$PROJECT_NAME"
cd "$PROJECTS_DIR/$PROJECT_NAME"

# Create empty queue file
touch "$QUEUE_DIR/$PROJECT_NAME.queue"

# Verify structure
if [ ! -f ".swarm/config.yaml" ]; then
  echo "WARNING: .swarm/config.yaml not found. Is this a swarm-template project?"
fi

if [ ! -f "swarm-state.json" ]; then
  echo "WARNING: swarm-state.json not found."
fi

# Update swarm config with project name and repo
if [ -f ".swarm/config.yaml" ]; then
  yq -i ".project_name = \"$PROJECT_NAME\"" .swarm/config.yaml
  yq -i ".repo = \"$(echo $GIT_URL | sed 's/.*github.com[:/]//' | sed 's/.git$//')\"" .swarm/config.yaml
fi

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || true

echo ""
echo "✅ Project registered successfully!"
echo ""
echo "  Location: $PROJECTS_DIR/$PROJECT_NAME"
echo "  Queue:    $QUEUE_DIR/$PROJECT_NAME.queue"
echo "  Logs:     $LOGS_DIR/${PROJECT_NAME}-*.log"
echo ""
echo "Next steps:"
echo "  1. Set env vars in $PROJECTS_DIR/$PROJECT_NAME/.env"
echo "  2. Ensure GitHub secrets (VPS_HOST, VPS_SSH_KEY) are configured"
echo "  3. Stakeholders can now create issues and label them 'ready-to-build'"
