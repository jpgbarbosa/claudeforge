#!/bin/bash
# orchestrator.sh — Main swarm orchestrator
# Runs on VPS, processes one issue at a time
# Usage: ./orchestrator.sh /path/to/project

set -euo pipefail

PROJECT_DIR="${1:?Usage: ./orchestrator.sh /path/to/project}"
cd "$PROJECT_DIR"

SWARM_DIR=".swarm"
STATE_FILE="swarm-state.json"
GITHUB_SCRIPT="./scripts/github-integration.sh"
MAX_RETRIES=3

log() {
  echo "[SWARM $(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$SWARM_DIR/logs/orchestrator.log"
}

read_state() {
  jq -r "$1" "$STATE_FILE"
}

update_state() {
  local tmp=$(mktemp)
  jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

run_agent() {
  local agent_name="$1"
  local prompt_file="$SWARM_DIR/prompts/${agent_name}.md"
  local retries=0

  log "Running agent: $agent_name"

  while [ $retries -lt $MAX_RETRIES ]; do
    if claude --prompt-file "$prompt_file" 2>&1 | tee -a "$SWARM_DIR/logs/${agent_name}.log"; then
      log "Agent $agent_name completed successfully"
      return 0
    fi

    retries=$((retries + 1))

    # Check if it's a rate limit
    if grep -q "rate_limit\|429\|overloaded" "$SWARM_DIR/logs/${agent_name}.log" 2>/dev/null; then
      local backoff=$(yq -r '.rate_limit_backoff_seconds // 300' "$SWARM_DIR/config.yaml")
      log "Rate limited. Waiting ${backoff}s before retry ($retries/$MAX_RETRIES)"
      sleep "$backoff"
    else
      log "Agent $agent_name failed (attempt $retries/$MAX_RETRIES)"
      sleep 30
    fi
  done

  log "ERROR: Agent $agent_name failed after $MAX_RETRIES attempts"
  update_state '.status = "error" | .last_agent = "'"$agent_name"'"'
  return 1
}

commit_and_push() {
  local message="$1"
  git add -A
  if git diff --cached --quiet; then
    log "No changes to commit"
  else
    git commit -m "$message"
    git push origin HEAD
    log "Committed and pushed: $message"
  fi
}

wait_for_human() {
  local channel=$(read_state '.human_input_channel')
  log "Waiting for human input on $channel..."

  while [ "$(read_state '.human_input_needed')" = "true" ]; do
    sleep 120 # Check every 2 minutes
    git pull origin HEAD --rebase 2>/dev/null || true

    # Re-read state in case human (or a webhook) updated it
    if [ "$(read_state '.human_input_needed')" = "false" ]; then
      log "Human input received. Resuming."
      return 0
    fi
  done
}

# --- Main loop ---

log "Starting orchestrator for project: $PROJECT_DIR"
git pull origin HEAD --rebase 2>/dev/null || true

STAGE=$(read_state '.current_stage')
STATUS=$(read_state '.status')

if [ "$STATUS" = "idle" ]; then
  log "No active issue. Exiting."
  exit 0
fi

log "Current stage: $STAGE | Status: $STATUS"

# Check for pending human input
if [ "$(read_state '.human_input_needed')" = "true" ]; then
  wait_for_human
  STAGE=$(read_state '.current_stage')
fi

case "$STAGE" in
  "discovery")
    run_agent "business-analyst"
    commit_and_push "swarm: business analysis complete"

    run_agent "product-strategist"
    commit_and_push "swarm: product spec complete"

    run_agent "architect"
    commit_and_push "swarm: architecture complete"

    update_state '.current_stage = "planning"'
    commit_and_push "swarm: discovery stage complete"
    ;;

  "planning")
    run_agent "tech-lead"
    commit_and_push "swarm: implementation plan ready"

    # Open draft PR for stakeholder review
    source "$GITHUB_SCRIPT"
    gh_open_draft_pr

    update_state '.human_input_needed = true | .human_input_channel = "pr"'
    commit_and_push "swarm: awaiting plan approval on PR"

    wait_for_human
    update_state '.current_stage = "development" | .current_task_index = 0'
    commit_and_push "swarm: plan approved, starting development"
    ;;

  "development")
    TOTAL=$(read_state '.total_tasks')
    CURRENT=$(read_state '.current_task_index')

    while [ "$CURRENT" -lt "$TOTAL" ]; do
      log "Task $((CURRENT + 1))/$TOTAL"
      run_agent "developer"
      commit_and_push "swarm: task $((CURRENT + 1))/$TOTAL complete"

      CURRENT=$(read_state '.current_task_index')

      # Check for feedback from visual QA (rework cycle)
      if [ "$(read_state '.current_stage')" != "development" ]; then
        break
      fi
    done

    if [ "$CURRENT" -ge "$TOTAL" ]; then
      update_state '.current_stage = "visual_qa"'
      commit_and_push "swarm: all tasks complete, starting visual QA"
    fi
    ;;

  "visual_qa")
    run_agent "visual-qa"
    commit_and_push "swarm: visual QA complete"

    # Check if QA sent it back to development
    if [ "$(read_state '.current_stage')" = "development" ]; then
      log "Visual QA found issues. Returning to development."
    else
      update_state '.current_stage = "review"'
      commit_and_push "swarm: visual QA passed, starting review"
    fi
    ;;

  "review")
    run_agent "reviewer"
    commit_and_push "swarm: review complete, awaiting tech review"

    # PR is now ready for human tech review
    source "$GITHUB_SCRIPT"
    gh_mark_pr_ready

    update_state '.status = "awaiting_tech_review" | .human_input_needed = true | .human_input_channel = "pr"'
    commit_and_push "swarm: ready for tech review"

    log "Done. PR is ready for tech review."
    ;;

  *)
    log "Unknown stage: $STAGE"
    exit 1
    ;;
esac

log "Orchestrator run complete. Stage: $(read_state '.current_stage') | Status: $(read_state '.status')"
