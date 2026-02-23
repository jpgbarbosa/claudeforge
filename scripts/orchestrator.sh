#!/bin/bash
# orchestrator.sh — Main swarm orchestrator
# Single-invocation state machine executor, run by GitHub Actions
# Usage: ./scripts/orchestrator.sh <discovery|build>

set -euo pipefail

MODE="${1:?Usage: ./scripts/orchestrator.sh <discovery|build>}"

SWARM_DIR=".swarm"
STATE_FILE="swarm-state.json"
GITHUB_SCRIPT="./scripts/github-integration.sh"
MAX_RETRIES=3
MAX_QA_CYCLES=3

mkdir -p "$SWARM_DIR/logs"

if [ ! -f "$STATE_FILE" ]; then
  echo "[SWARM] ERROR: $STATE_FILE not found" >&2
  exit 1
fi
if ! jq empty "$STATE_FILE" 2>/dev/null; then
  echo "[SWARM] ERROR: $STATE_FILE is invalid JSON" >&2
  exit 1
fi

log() {
  echo "[SWARM $(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$SWARM_DIR/logs/orchestrator.log"
}

read_state() {
  jq -r "$1" "$STATE_FILE"
}

update_state() {
  local filter="$1"
  shift
  local tmp=$(mktemp)
  jq "$@" "$filter" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

run_agent() {
  local agent_name="$1"
  local prompt_file="$SWARM_DIR/prompts/${agent_name}.md"
  local retries=0

  local model
  model=$(yq -r '.model // "claude-sonnet-4-20250514"' "$SWARM_DIR/config.yaml")

  log "Running agent: $agent_name (model: $model)"

  while [ $retries -lt $MAX_RETRIES ]; do
    if claude -p --model "$model" --dangerously-skip-permissions "$(cat "$prompt_file")" 2>&1 | tee -a "$SWARM_DIR/logs/${agent_name}.log"; then
      log "Agent $agent_name completed successfully"
      update_state '.last_agent = $agent | .last_updated = (now | tostring)' --arg agent "$agent_name"
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
  update_state '.status = "error" | .last_agent = $agent' --arg agent "$agent_name"
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

check_human_gate() {
  if [ "$(read_state '.human_input_needed')" = "true" ]; then
    log "Human input needed. Committing state and exiting."
    commit_and_push "swarm: awaiting human input"
    exit 42
  fi
}

# --- Main ---

log "Starting orchestrator in $MODE mode"

STAGE=$(read_state '.current_stage')
STATUS=$(read_state '.status')
LAST_AGENT=$(read_state '.last_agent')
RESUME_AGENT=$(read_state '.resume_agent // "null"')

log "Current stage: $STAGE | Status: $STATUS | Last agent: $LAST_AGENT | Resume agent: $RESUME_AGENT"

check_human_gate

case "$MODE" in
  "discovery")
    # Discovery: BA → PS → Architect (resume from last_agent if re-invoked)
    DISCOVERY_AGENTS=("business-analyst" "product-strategist" "architect")
    SKIP=true

    # If no last agent, start from the beginning
    if [ "$LAST_AGENT" = "null" ] || [ -z "$LAST_AGENT" ]; then
      SKIP=false
    fi

    for agent in "${DISCOVERY_AGENTS[@]}"; do
      if [ "$SKIP" = true ]; then
        if [ "$agent" = "$LAST_AGENT" ]; then
          SKIP=false
          if [ "$RESUME_AGENT" != "$agent" ]; then
            continue  # completed normally, skip
          fi
          # resume_agent matches — fall through to re-run
          log "Re-running agent $agent (resume_agent match)"
          update_state '.resume_agent = null'
        else
          continue
        fi
      fi

      run_agent "$agent"
      commit_and_push "swarm: $agent complete"
      check_human_gate
    done

    # Planning: Tech Lead → open draft PR
    update_state '.current_stage = "planning"'
    commit_and_push "swarm: discovery complete, starting planning"

    run_agent "tech-lead"
    commit_and_push "swarm: implementation plan ready"

    # Open draft PR for stakeholder review
    source "$GITHUB_SCRIPT"
    gh_open_draft_pr

    update_state '.human_input_needed = true | .human_input_channel = "pr" | .current_stage = "planning"'
    commit_and_push "swarm: awaiting plan approval on PR"

    log "Discovery complete. Draft PR opened, awaiting plan approval."
    ;;

  "build")
    # Development → Visual QA → Review (with bounded QA rework cycles)
    QA_CYCLE=0
    STAGE=$(read_state '.current_stage')

    while [ "$QA_CYCLE" -lt "$MAX_QA_CYCLES" ]; do
      # Development loop
      if [ "$STAGE" = "development" ] || [ "$STAGE" = "planning" ]; then
        update_state '.current_stage = "development"'
        TOTAL=$(read_state '.total_tasks')
        CURRENT=$(read_state '.current_task_index')

        while [ "$CURRENT" -lt "$TOTAL" ]; do
          log "Task $((CURRENT + 1))/$TOTAL"
          run_agent "developer"
          commit_and_push "swarm: task $((CURRENT + 1))/$TOTAL complete"

          CURRENT=$(read_state '.current_task_index')

          # Check if stage changed (e.g., QA rework cycle)
          if [ "$(read_state '.current_stage')" != "development" ]; then
            break
          fi
        done

        if [ "$CURRENT" -ge "$TOTAL" ]; then
          update_state '.current_stage = "visual_qa"'
          commit_and_push "swarm: all tasks complete, starting visual QA"
        fi

        STAGE=$(read_state '.current_stage')
      fi

      # Visual QA
      if [ "$STAGE" = "visual_qa" ]; then
        run_agent "visual-qa"
        commit_and_push "swarm: visual QA complete"

        # Check if QA sent it back to development
        if [ "$(read_state '.current_stage')" = "development" ]; then
          QA_CYCLE=$((QA_CYCLE + 1))
          log "Visual QA found issues. Returning to development (cycle $QA_CYCLE/$MAX_QA_CYCLES)."
          STAGE="development"
          continue
        fi

        update_state '.current_stage = "review"'
        commit_and_push "swarm: visual QA passed, starting review"
        STAGE="review"
      fi

      # Review
      if [ "$STAGE" = "review" ]; then
        run_agent "reviewer"
        commit_and_push "swarm: review complete, awaiting tech review"

        # PR is now ready for human tech review
        source "$GITHUB_SCRIPT"
        gh_mark_pr_ready

        update_state '.status = "awaiting_tech_review" | .human_input_needed = true | .human_input_channel = "pr"'
        commit_and_push "swarm: ready for tech review"

        log "Done. PR is ready for tech review."
        break
      fi

      break  # Exit loop if stage is not development/planning/visual_qa/review
    done

    if [ "$QA_CYCLE" -ge "$MAX_QA_CYCLES" ]; then
      log "ERROR: QA rework limit reached ($MAX_QA_CYCLES cycles). Stopping."
      update_state '.status = "error" | .last_agent = "visual-qa"'
      commit_and_push "swarm: QA rework limit reached"
      exit 1
    fi
    ;;

  *)
    log "Unknown mode: $MODE (expected 'discovery' or 'build')"
    exit 1
    ;;
esac

log "Orchestrator run complete. Stage: $(read_state '.current_stage') | Status: $(read_state '.status')"
