#!/bin/bash
# test-workflow-logic.sh — Test the shell logic extracted from workflow run: blocks
# Run: ./tests/test-workflow-logic.sh
#
# Tests the state-machine logic (resume, gates, stage transitions) that
# lives in the workflow YAML's bash steps. Does NOT test claude-code-action
# invocations (those only run on GitHub).

set -euo pipefail

PASS=0
FAIL=0
TESTS=()

# Capture repo root before any cd
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Test helpers ---

setup() {
  TEST_DIR=$(mktemp -d)
  cp swarm-state.json "$TEST_DIR/swarm-state.json"
  cd "$TEST_DIR"
}

teardown() {
  cd - > /dev/null
  rm -rf "$TEST_DIR"
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    TESTS+=("  PASS: $label")
  else
    FAIL=$((FAIL + 1))
    TESTS+=("  FAIL: $label (expected '$expected', got '$actual')")
  fi
}

# --- Discovery: resume logic ---

test_discovery_resume_fresh_start() {
  setup
  jq '.last_agent = null | .resume_agent = null' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  LAST=$(jq -r '.last_agent // ""' swarm-state.json)
  RESUME=$(jq -r '.resume_agent // ""' swarm-state.json)

  # BA check: run if no last agent
  if [ -z "$LAST" ] || [ "$LAST" = "null" ] || [ "$RESUME" = "business-analyst" ]; then
    BA_RUN="true"
  else
    BA_RUN="false"
  fi
  assert_eq "fresh start: BA runs" "$BA_RUN" "true"

  teardown
}

test_discovery_resume_after_ba() {
  setup
  jq '.last_agent = "business-analyst" | .resume_agent = null' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  LAST=$(jq -r '.last_agent // ""' swarm-state.json)
  RESUME=$(jq -r '.resume_agent // ""' swarm-state.json)

  # BA check
  if [ -z "$LAST" ] || [ "$LAST" = "null" ] || [ "$RESUME" = "business-analyst" ]; then
    BA_RUN="true"
  else
    BA_RUN="false"
  fi
  assert_eq "after BA: BA skipped" "$BA_RUN" "false"

  # PS check
  BA_RAN="$BA_RUN"
  if [ "$BA_RAN" = "true" ] || [ "$RESUME" = "product-strategist" ] || [ "$LAST" = "business-analyst" ]; then
    PS_RUN="true"
  else
    PS_RUN="false"
  fi
  assert_eq "after BA: PS runs" "$PS_RUN" "true"

  teardown
}

test_discovery_resume_after_ps() {
  setup
  jq '.last_agent = "product-strategist" | .resume_agent = null' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  LAST=$(jq -r '.last_agent // ""' swarm-state.json)
  RESUME=$(jq -r '.resume_agent // ""' swarm-state.json)

  # BA check
  if [ -z "$LAST" ] || [ "$LAST" = "null" ] || [ "$RESUME" = "business-analyst" ]; then
    BA_RUN="true"
  else
    BA_RUN="false"
  fi
  assert_eq "after PS: BA skipped" "$BA_RUN" "false"

  # PS check (workflow checks: BA ran, or resume=PS, or last=BA)
  BA_RAN="$BA_RUN"
  if [ "$BA_RAN" = "true" ] || [ "$RESUME" = "product-strategist" ] || [ "$LAST" = "business-analyst" ]; then
    PS_RUN="true"
  else
    PS_RUN="false"
  fi
  assert_eq "after PS: PS skipped" "$PS_RUN" "false"

  # Arch check
  PS_RAN="$PS_RUN"
  if [ "$PS_RAN" = "true" ] || [ "$RESUME" = "architect" ] || [ "$LAST" = "product-strategist" ]; then
    ARCH_RUN="true"
  else
    ARCH_RUN="false"
  fi
  assert_eq "after PS: Architect runs" "$ARCH_RUN" "true"

  teardown
}

test_discovery_resume_ba_with_resume_agent() {
  setup
  jq '.last_agent = "business-analyst" | .resume_agent = "business-analyst"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  LAST=$(jq -r '.last_agent // ""' swarm-state.json)
  RESUME=$(jq -r '.resume_agent // ""' swarm-state.json)

  if [ -z "$LAST" ] || [ "$LAST" = "null" ] || [ "$RESUME" = "business-analyst" ]; then
    BA_RUN="true"
  else
    BA_RUN="false"
  fi
  assert_eq "resume BA: BA re-runs" "$BA_RUN" "true"

  teardown
}

# --- Discovery: human gate ---

test_discovery_human_gate_blocks() {
  setup
  jq '.human_input_needed = true' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  BLOCKED="false"
  if [ "$(jq -r '.human_input_needed' swarm-state.json)" = "true" ]; then
    BLOCKED="true"
  fi
  assert_eq "human gate blocks when needed" "$BLOCKED" "true"

  teardown
}

test_discovery_human_gate_passes() {
  setup
  jq '.human_input_needed = false' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  BLOCKED="false"
  if [ "$(jq -r '.human_input_needed' swarm-state.json)" = "true" ]; then
    BLOCKED="true"
  fi
  assert_eq "human gate passes when not needed" "$BLOCKED" "false"

  teardown
}

# --- Build: state update logic ---

test_build_state_from_planning() {
  setup
  jq '.current_stage = "planning" | .current_task_index = 0' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  STAGE=$(jq -r '.current_stage' swarm-state.json)
  if [ "$STAGE" = "planning" ] || [ "$STAGE" = "idle" ]; then
    jq '.current_stage = "development" | .current_task_index = 0 | .human_input_needed = false' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  fi
  STAGE=$(jq -r '.current_stage' swarm-state.json)

  assert_eq "planning -> development" "$STAGE" "development"

  teardown
}

test_build_state_resume_from_development() {
  setup
  jq '.current_stage = "development" | .current_task_index = 3 | .total_tasks = 5' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  STAGE=$(jq -r '.current_stage' swarm-state.json)
  INDEX=$(jq -r '.current_task_index' swarm-state.json)
  if [ "$STAGE" = "planning" ] || [ "$STAGE" = "idle" ]; then
    jq '.current_stage = "development" | .current_task_index = 0 | .human_input_needed = false' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  else
    jq '.human_input_needed = false' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  fi

  STAGE=$(jq -r '.current_stage' swarm-state.json)
  INDEX=$(jq -r '.current_task_index' swarm-state.json)
  assert_eq "resume dev: stage stays development" "$STAGE" "development"
  assert_eq "resume dev: task index preserved" "$INDEX" "3"

  teardown
}

test_build_state_resume_from_review() {
  setup
  jq '.current_stage = "review"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  STAGE=$(jq -r '.current_stage' swarm-state.json)
  if [ "$STAGE" = "planning" ] || [ "$STAGE" = "idle" ]; then
    jq '.current_stage = "development" | .current_task_index = 0 | .human_input_needed = false' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  else
    jq '.human_input_needed = false' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  fi
  STAGE=$(jq -r '.current_stage' swarm-state.json)

  assert_eq "resume review: stage stays review" "$STAGE" "review"

  teardown
}

# --- Build: post-dev task completion check ---

test_postdev_all_tasks_complete() {
  setup
  jq '.current_task_index = 5 | .total_tasks = 5' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  TOTAL=$(jq -r '.total_tasks // 0' swarm-state.json)
  CURRENT=$(jq -r '.current_task_index // 0' swarm-state.json)

  if [ "$TOTAL" -gt 0 ] && [ "$CURRENT" -lt "$TOTAL" ] 2>/dev/null; then
    TASKS_DONE="false"
  else
    TASKS_DONE="true"
  fi
  assert_eq "all tasks done: advances" "$TASKS_DONE" "true"

  teardown
}

test_postdev_tasks_incomplete() {
  setup
  jq '.current_task_index = 3 | .total_tasks = 5' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  TOTAL=$(jq -r '.total_tasks // 0' swarm-state.json)
  CURRENT=$(jq -r '.current_task_index // 0' swarm-state.json)

  if [ "$TOTAL" -gt 0 ] && [ "$CURRENT" -lt "$TOTAL" ] 2>/dev/null; then
    TASKS_DONE="false"
  else
    TASKS_DONE="true"
  fi
  assert_eq "tasks incomplete: stays in dev" "$TASKS_DONE" "false"

  teardown
}

test_postdev_zero_tasks() {
  setup
  jq '.current_task_index = 0 | .total_tasks = 0' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  TOTAL=$(jq -r '.total_tasks // 0' swarm-state.json)
  CURRENT=$(jq -r '.current_task_index // 0' swarm-state.json)

  if [ "$TOTAL" -gt 0 ] && [ "$CURRENT" -lt "$TOTAL" ] 2>/dev/null; then
    TASKS_DONE="false"
  else
    TASKS_DONE="true"
  fi
  assert_eq "zero tasks: advances (edge case)" "$TASKS_DONE" "true"

  teardown
}

# --- Build: QA check logic ---

test_qa_check_passed() {
  setup
  # Simulate QA agent leaving stage as visual_qa (didn't send back to dev)
  jq '.current_stage = "visual_qa"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  STAGE=$(jq -r '.current_stage' swarm-state.json)
  if [ "$STAGE" = "development" ]; then
    QA_PASSED="false"
  else
    QA_PASSED="true"
  fi
  assert_eq "QA passed: stage not development" "$QA_PASSED" "true"

  teardown
}

test_qa_check_failed() {
  setup
  # Simulate QA agent sending back to development
  jq '.current_stage = "development"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  STAGE=$(jq -r '.current_stage' swarm-state.json)
  if [ "$STAGE" = "development" ]; then
    QA_PASSED="false"
  else
    QA_PASSED="true"
  fi
  assert_eq "QA failed: stage is development" "$QA_PASSED" "false"

  teardown
}

# --- Build: step condition simulation ---
# Simulates the GH Actions if: logic using string comparisons

test_step_conditions_fresh_build() {
  # stage=development, all QA outputs empty (not yet run)
  STAGE="development"
  QA1_PASSED="" QA2_PASSED="" QA3_PASSED=""
  POST_DEV_TASKS_DONE="true"

  # Dev step
  DEV_RUNS=$([[ "$STAGE" == "development" ]] && echo "true" || echo "false")
  assert_eq "fresh build: dev runs" "$DEV_RUNS" "true"

  # QA1
  QA1_RUNS=$([[ "$STAGE" != "review" && "$POST_DEV_TASKS_DONE" != "false" ]] && echo "true" || echo "false")
  assert_eq "fresh build: QA1 runs" "$QA1_RUNS" "true"

  # Reviewer (needs QA pass or stage==review)
  REVIEWER_RUNS="false"
  [[ "$STAGE" == "review" || "$QA1_PASSED" == "true" || "$QA2_PASSED" == "true" || "$QA3_PASSED" == "true" ]] && REVIEWER_RUNS="true"
  assert_eq "fresh build: reviewer waits for QA" "$REVIEWER_RUNS" "false"
}

test_step_conditions_resume_review() {
  STAGE="review"
  QA1_PASSED="" QA2_PASSED="" QA3_PASSED=""
  POST_DEV_TASKS_DONE=""

  # Dev step
  DEV_RUNS=$([[ "$STAGE" == "development" ]] && echo "true" || echo "false")
  assert_eq "resume review: dev skipped" "$DEV_RUNS" "false"

  # QA1
  QA1_RUNS=$([[ "$STAGE" != "review" ]] && echo "true" || echo "false")
  assert_eq "resume review: QA1 skipped" "$QA1_RUNS" "false"

  # Reviewer
  REVIEWER_RUNS="false"
  [[ "$STAGE" == "review" || "$QA1_PASSED" == "true" || "$QA2_PASSED" == "true" || "$QA3_PASSED" == "true" ]] && REVIEWER_RUNS="true"
  assert_eq "resume review: reviewer runs" "$REVIEWER_RUNS" "true"

  # QA failure gate
  QA_GATE_FIRES="false"
  [[ "$STAGE" != "review" && "$QA1_PASSED" == "false" && "$QA2_PASSED" == "false" && "$QA3_PASSED" == "false" ]] && QA_GATE_FIRES="true"
  assert_eq "resume review: QA gate does NOT fire" "$QA_GATE_FIRES" "false"
}

test_step_conditions_resume_visual_qa() {
  STAGE="visual_qa"
  QA1_PASSED="" QA2_PASSED="" QA3_PASSED=""
  POST_DEV_TASKS_DONE=""

  # Dev step
  DEV_RUNS=$([[ "$STAGE" == "development" ]] && echo "true" || echo "false")
  assert_eq "resume QA: dev skipped" "$DEV_RUNS" "false"

  # QA1 (post_dev didn't run, so tasks_done is empty)
  QA1_RUNS=$([[ "$STAGE" != "review" && "$POST_DEV_TASKS_DONE" != "false" ]] && echo "true" || echo "false")
  assert_eq "resume QA: QA1 runs" "$QA1_RUNS" "true"
}

test_step_conditions_dev_incomplete() {
  STAGE="development"
  POST_DEV_TASKS_DONE="false"

  # QA1 should NOT run if dev didn't finish
  QA1_RUNS=$([[ "$STAGE" != "review" && "$POST_DEV_TASKS_DONE" != "false" ]] && echo "true" || echo "false")
  assert_eq "dev incomplete: QA1 skipped" "$QA1_RUNS" "false"
}

# --- github-integration.sh: get_repo ---

test_get_repo_env_var() {
  setup
  mkdir -p .swarm
  echo 'repo: "org/project"' > .swarm/config.yaml

  source "$REPO_ROOT/scripts/github-integration.sh" 2>/dev/null || true

  GITHUB_REPOSITORY="env-org/env-project"
  RESULT=$(get_repo)
  assert_eq "get_repo: prefers env var" "$RESULT" "env-org/env-project"
  unset GITHUB_REPOSITORY

  teardown
}

test_get_repo_grep_double_quotes() {
  setup
  mkdir -p .swarm
  echo 'repo: "org/project"' > .swarm/config.yaml

  source "$REPO_ROOT/scripts/github-integration.sh" 2>/dev/null || true

  unset GITHUB_REPOSITORY
  RESULT=$(get_repo)
  assert_eq "get_repo: strips double quotes" "$RESULT" "org/project"

  teardown
}

test_get_repo_grep_single_quotes() {
  setup
  mkdir -p .swarm
  echo "repo: 'org/project'" > .swarm/config.yaml

  source "$REPO_ROOT/scripts/github-integration.sh" 2>/dev/null || true

  unset GITHUB_REPOSITORY
  RESULT=$(get_repo)
  assert_eq "get_repo: strips single quotes" "$RESULT" "org/project"

  teardown
}

test_get_repo_grep_no_quotes() {
  setup
  mkdir -p .swarm
  echo 'repo: org/project' > .swarm/config.yaml

  source "$REPO_ROOT/scripts/github-integration.sh" 2>/dev/null || true

  unset GITHUB_REPOSITORY
  RESULT=$(get_repo)
  assert_eq "get_repo: works without quotes" "$RESULT" "org/project"

  teardown
}

# --- Run all tests ---

echo "=== Workflow Logic Tests ==="
echo ""

echo "--- Discovery: Resume Logic ---"
test_discovery_resume_fresh_start
test_discovery_resume_after_ba
test_discovery_resume_after_ps
test_discovery_resume_ba_with_resume_agent

echo ""
echo "--- Discovery: Human Gate ---"
test_discovery_human_gate_blocks
test_discovery_human_gate_passes

echo ""
echo "--- Build: State Update ---"
test_build_state_from_planning
test_build_state_resume_from_development
test_build_state_resume_from_review

echo ""
echo "--- Build: Post-Dev Task Check ---"
test_postdev_all_tasks_complete
test_postdev_tasks_incomplete
test_postdev_zero_tasks

echo ""
echo "--- Build: QA Check ---"
test_qa_check_passed
test_qa_check_failed

echo ""
echo "--- Build: Step Conditions ---"
test_step_conditions_fresh_build
test_step_conditions_resume_review
test_step_conditions_resume_visual_qa
test_step_conditions_dev_incomplete

echo ""
echo "--- github-integration.sh: get_repo ---"
test_get_repo_env_var
test_get_repo_grep_double_quotes
test_get_repo_grep_single_quotes
test_get_repo_grep_no_quotes

echo ""
echo "=== Results ==="
for t in "${TESTS[@]}"; do echo "$t"; done
echo ""
echo "Total: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
