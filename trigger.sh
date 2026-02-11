#!/bin/bash
# trigger.sh — Called by GitHub Actions when an issue gets the ready-to-build label
# Usage: ./trigger.sh org/repo-name 42
# Lives on VPS at /opt/swarm-platform/trigger.sh

set -euo pipefail

REPO="${1:?Usage: ./trigger.sh org/repo issue_number}"
ISSUE_NUMBER="${2:?Usage: ./trigger.sh org/repo issue_number}"
PLATFORM_DIR="/opt/swarm-platform"
PROJECTS_DIR="$PLATFORM_DIR/projects"

# Derive project name from repo
PROJECT_NAME=$(echo "$REPO" | cut -d'/' -f2)
PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"

log() {
  echo "[TRIGGER $(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$PLATFORM_DIR/logs/trigger.log"
}

log "Received trigger: $REPO issue #$ISSUE_NUMBER"

# Check if project is registered
if [ ! -d "$PROJECT_DIR" ]; then
  log "ERROR: Project $PROJECT_NAME not registered. Run register-project.sh first."
  exit 1
fi

cd "$PROJECT_DIR"

# Check if swarm is already working on something
CURRENT_STATUS=$(jq -r '.status' swarm-state.json)
if [ "$CURRENT_STATUS" != "idle" ] && [ "$CURRENT_STATUS" != "completed" ]; then
  log "Swarm is busy (status: $CURRENT_STATUS). Queuing issue #$ISSUE_NUMBER."
  # Add to queue file
  echo "$ISSUE_NUMBER" >> "$PLATFORM_DIR/queue/$PROJECT_NAME.queue"
  exit 0
fi

# Pull latest
git pull origin main --rebase

# Create feature branch
BRANCH="swarm/issue-${ISSUE_NUMBER}"
git checkout -b "$BRANCH" main

# Initialize state for this issue
jq --arg issue "$ISSUE_NUMBER" --arg repo "$REPO" \
  '.current_issue = ($issue | tonumber) |
   .current_stage = "discovery" |
   .status = "in_progress" |
   .last_updated = (now | todate) |
   .human_input_needed = false |
   .open_questions = [] |
   .feedback_pending = [] |
   .tasks = [] |
   .total_tasks = 0 |
   .current_task_index = 0' \
  swarm-state.json > tmp.json && mv tmp.json swarm-state.json

git add swarm-state.json
git commit -m "swarm: start issue #$ISSUE_NUMBER"
git push -u origin "$BRANCH"

# Update label
gh issue edit "$ISSUE_NUMBER" --repo "$REPO" --add-label "swarm-working" --remove-label "ready-to-build"

log "Branch $BRANCH created. Starting orchestrator."

# Run orchestrator in background
nohup bash scripts/orchestrator.sh "$PROJECT_DIR" \
  >> "$PLATFORM_DIR/logs/${PROJECT_NAME}-${ISSUE_NUMBER}.log" 2>&1 &

log "Orchestrator started (PID: $!)"
