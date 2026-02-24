#!/bin/bash
# test-integration.sh — End-to-end integration tests for swarm workflows
# Run: ./tests/test-integration.sh
#
# Simulates the full workflow shell logic locally with mocked gh/git.
# Tests all 3 tier paths (bugfix, enhancement, feature) end-to-end,
# plus build paths, state management, and GitHub integration helpers.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL_GIT="$(which git)"
export REAL_GIT
PASS=0
FAIL=0
TESTS=()

# ============================================================
# Setup / Teardown
# ============================================================

setup_test_env() {
  TEST_DIR=$(mktemp -d)
  MOCK_DIR="$TEST_DIR/mocks"
  MOCK_GH_LOG="$TEST_DIR/gh-calls.log"
  MOCK_GIT_LOG="$TEST_DIR/git-calls.log"
  export GITHUB_OUTPUT="$TEST_DIR/github-output"
  export GITHUB_REPOSITORY="test-org/test-repo"
  export GH_TOKEN="mock-token"
  export MOCK_GH_LOG MOCK_GIT_LOG

  touch "$GITHUB_OUTPUT" "$MOCK_GH_LOG" "$MOCK_GIT_LOG"

  # Create mock gh
  mkdir -p "$MOCK_DIR"
  cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/bin/bash
echo "$@" >> "$MOCK_GH_LOG"
case "$1 $2" in
  "issue view")   echo '{"title":"[Bug]: Fix button","labels":[{"name":"ready-to-build"}]}' ;;
  "issue edit")   echo "ok" ;;
  "issue comment") echo "ok" ;;
  "pr list")      echo "[]" ;;
  "pr create")    echo "https://github.com/test/repo/pull/1" ;;
  "pr ready")     echo "ok" ;;
  "pr view")      echo '{"headRefName":"swarm/issue-1"}' ;;
  "api "*)        echo '{"permission":"write"}' ;;
  *)              echo "mock-gh: unhandled: $*" >&2 ;;
esac
MOCK_GH
  chmod +x "$MOCK_DIR/gh"

  # Resolve real git path before mocking
  REAL_GIT="$(which git)"
  export REAL_GIT

  # Create mock git — intercepts network ops, passes through local ops
  cat > "$MOCK_DIR/git" << 'MOCK_GIT'
#!/bin/bash
case "$1" in
  push|pull|fetch|remote|ls-remote)
    echo "[mock-git] $*" >> "$MOCK_GIT_LOG"
    ;;
  *)
    "$REAL_GIT" "$@"
    ;;
esac
MOCK_GIT
  chmod +x "$MOCK_DIR/git"

  # Put mocks first on PATH
  export ORIGINAL_PATH="$PATH"
  export PATH="$MOCK_DIR:$PATH"

  # Initialize a real git repo in the test dir (needed for local git ops)
  cd "$TEST_DIR"
  "$REAL_GIT" init -q
  "$REAL_GIT" config user.name "test"
  "$REAL_GIT" config user.email "test@test.com"

  # Create clean idle state (don't rely on repo's current state)
  cat > "$TEST_DIR/swarm-state.json" << 'STATE'
{
  "project": "",
  "current_issue": null,
  "current_stage": "idle",
  "current_task_index": 0,
  "total_tasks": 0,
  "status": "idle",
  "last_agent": null,
  "last_updated": null,
  "issue_tier": null,
  "requires_visual_qa": true,
  "human_input_needed": false,
  "human_input_channel": null,
  "open_questions": [],
  "feedback_pending": [],
  "tasks": []
}
STATE
  cp -r "$REPO_ROOT/scripts" "$TEST_DIR/scripts" 2>/dev/null || true
  mkdir -p "$TEST_DIR/.swarm/logs" "$TEST_DIR/docs"

  # Create initial commit so git operations work
  "$REAL_GIT" add -A
  "$REAL_GIT" commit -q -m "init"

  # Create config for github-integration.sh
  mkdir -p .swarm
  echo 'repo: "test-org/test-repo"' > .swarm/config.yaml
}

teardown_test_env() {
  cd "$REPO_ROOT"
  export PATH="$ORIGINAL_PATH"
  rm -rf "$TEST_DIR"
}

# ============================================================
# Helpers
# ============================================================

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

read_output() {
  grep "^$1=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2
}

read_state() {
  jq -r "$1" swarm-state.json
}

# Reset GITHUB_OUTPUT between steps (simulates fresh step output)
reset_output() {
  > "$GITHUB_OUTPUT"
}

# ============================================================
# Extracted workflow steps (from swarm-discovery.yaml)
# ============================================================

run_init_state() {
  local ISSUE="$1"
  STATUS=$(jq -r '.status' swarm-state.json)
  if [ "$STATUS" = "idle" ]; then
    jq --argjson issue "$ISSUE" \
      '.current_issue = $issue | .status = "active" | .current_stage = "discovery" | .last_updated = now | .human_input_needed = false' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  fi
  mkdir -p .swarm/logs
}

run_human_gate() {
  reset_output
  if [ "$(jq -r '.human_input_needed' swarm-state.json)" = "true" ]; then
    echo "blocked=true" >> "$GITHUB_OUTPUT"
  else
    echo "blocked=false" >> "$GITHUB_OUTPUT"
  fi
}

run_read_resume_state() {
  reset_output
  LAST_AGENT=$(jq -r '.last_agent // ""' swarm-state.json)
  RESUME_AGENT=$(jq -r '.resume_agent // ""' swarm-state.json)
  echo "last_agent=$LAST_AGENT" >> "$GITHUB_OUTPUT"
  echo "resume_agent=$RESUME_AGENT" >> "$GITHUB_OUTPUT"
}

run_triage() {
  local ISSUE="$1" MOCK_TITLE="$2" MOCK_LABELS="${3:-}"
  reset_output

  EXISTING_TIER=$(jq -r '.issue_tier // ""' swarm-state.json)
  if [ -n "$EXISTING_TIER" ] && [ "$EXISTING_TIER" != "null" ]; then
    echo "tier=$EXISTING_TIER" >> "$GITHUB_OUTPUT"
    return 0
  fi

  TITLE="$MOCK_TITLE"
  LABELS="$MOCK_LABELS"

  if echo "$LABELS" | grep -q "swarm-tier:bugfix"; then TIER="bugfix"
  elif echo "$LABELS" | grep -q "swarm-tier:enhancement"; then TIER="enhancement"
  elif echo "$LABELS" | grep -q "swarm-tier:feature"; then TIER="feature"
  elif echo "$TITLE" | grep -qi "^\[Bug\]:"; then TIER="bugfix"
  elif echo "$TITLE" | grep -qi "^\[Feature\]:"; then TIER="feature"
  else TIER="feature"
  fi

  echo "tier=$TIER" >> "$GITHUB_OUTPUT"
  jq --arg tier "$TIER" '.issue_tier = $tier' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
}

run_ba_check() {
  local LAST="$1" RESUME="$2"
  reset_output
  if [ -z "$LAST" ] || [ "$LAST" = "null" ] || [ "$RESUME" = "business-analyst" ]; then
    echo "run=true" >> "$GITHUB_OUTPUT"
  else
    echo "run=false" >> "$GITHUB_OUTPUT"
  fi
}

run_ba_dryrun_stub() {
  mkdir -p docs
  echo "# Mock business brief" > docs/business-brief.md
  jq '.last_agent = "business-analyst" | .human_input_needed = false' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
}

run_post_agent_update() {
  local AGENT="$1"
  jq --arg a "$AGENT" '.last_agent = $a | .resume_agent = null | .last_updated = (now | tostring)' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A
  "$REAL_GIT" diff --cached --quiet || "$REAL_GIT" commit -q -m "swarm: $AGENT complete"
}

run_human_gate_check() {
  reset_output
  if [ "$(jq -r '.human_input_needed' swarm-state.json)" = "true" ]; then
    echo "blocked=true" >> "$GITHUB_OUTPUT"
  else
    echo "blocked=false" >> "$GITHUB_OUTPUT"
  fi
}

run_ps_check() {
  local TIER="$1" LAST="$2" RESUME="$3" BA_RAN="$4"
  reset_output
  if [ "$TIER" != "feature" ]; then
    echo "run=false" >> "$GITHUB_OUTPUT"
  elif [ "$BA_RAN" = "true" ] || [ "$RESUME" = "product-strategist" ] || [ "$LAST" = "business-analyst" ]; then
    echo "run=true" >> "$GITHUB_OUTPUT"
  else
    echo "run=false" >> "$GITHUB_OUTPUT"
  fi
}

run_ps_dryrun_stub() {
  mkdir -p docs
  echo "# Mock product spec" > docs/product-spec.md
  jq '.last_agent = "product-strategist" | .human_input_needed = false' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
}

run_arch_check() {
  local TIER="$1" LAST="$2" RESUME="$3" PS_RAN="$4" BA_RAN="$5"
  reset_output
  if [ "$TIER" = "bugfix" ]; then
    echo "run=false" >> "$GITHUB_OUTPUT"
  elif [ "$TIER" = "enhancement" ] && { [ "$BA_RAN" = "true" ] || [ "$LAST" = "business-analyst" ]; }; then
    echo "run=true" >> "$GITHUB_OUTPUT"
  elif [ "$PS_RAN" = "true" ] || [ "$RESUME" = "architect" ] || [ "$LAST" = "product-strategist" ]; then
    echo "run=true" >> "$GITHUB_OUTPUT"
  else
    echo "run=false" >> "$GITHUB_OUTPUT"
  fi
}

run_arch_dryrun_stub() {
  mkdir -p docs
  echo "# Mock architecture spec" > docs/architecture-spec.md
  jq '.last_agent = "architect" | .human_input_needed = false' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
}

run_tl_dryrun_stub() {
  mkdir -p docs
  echo "# Mock implementation plan" > docs/plan.md
  jq '.last_agent = "tech-lead" | .human_input_needed = false | .total_tasks = 3 | .tasks = [{"title":"Mock task 1"},{"title":"Mock task 2"},{"title":"Mock task 3"}]' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
}

run_update_stage_planning() {
  jq '.current_stage = "planning"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A
  "$REAL_GIT" diff --cached --quiet || "$REAL_GIT" commit -q -m "swarm: discovery complete, starting planning"
}

# ============================================================
# Extracted workflow steps (from swarm-build.yaml)
# ============================================================

run_build_state_update() {
  reset_output
  STAGE=$(jq -r '.current_stage' swarm-state.json)
  if [ "$STAGE" = "planning" ] || [ "$STAGE" = "idle" ]; then
    jq '.current_stage = "development" | .current_task_index = 0 | .human_input_needed = false' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  else
    jq '.human_input_needed = false' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  fi
  STAGE=$(jq -r '.current_stage' swarm-state.json)
  echo "stage=$STAGE" >> "$GITHUB_OUTPUT"
  "$REAL_GIT" add -A
  "$REAL_GIT" diff --cached --quiet || "$REAL_GIT" commit -q -m "swarm: build triggered (stage: $STAGE)"
}

run_dev_dryrun_stub() {
  TOTAL=$(jq -r '.total_tasks // 0' swarm-state.json)
  jq --argjson t "$TOTAL" '.current_task_index = $t' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
}

run_post_dev_state() {
  reset_output
  TOTAL=$(jq -r '.total_tasks // 0' swarm-state.json)
  CURRENT=$(jq -r '.current_task_index // 0' swarm-state.json)

  if [ "$TOTAL" -gt 0 ] && [ "$CURRENT" -lt "$TOTAL" ] 2>/dev/null; then
    jq '.last_agent = "developer" | .last_updated = (now | tostring)' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
    echo "tasks_done=false" >> "$GITHUB_OUTPUT"
  else
    jq '.current_stage = "visual_qa" | .last_agent = "developer" | .last_updated = (now | tostring)' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
    echo "tasks_done=true" >> "$GITHUB_OUTPUT"
  fi
  "$REAL_GIT" add -A
  "$REAL_GIT" diff --cached --quiet || "$REAL_GIT" commit -q -m "swarm: development phase complete"
}

run_qa_needed_check() {
  reset_output
  TIER=$(jq -r '.issue_tier // "feature"' swarm-state.json)
  REQUIRES_QA=$(jq -r '.requires_visual_qa' swarm-state.json)
  if [ "$REQUIRES_QA" = "null" ]; then REQUIRES_QA="true"; fi

  if [ "$TIER" = "bugfix" ] && [ "$REQUIRES_QA" = "false" ]; then
    echo "skip_qa=true" >> "$GITHUB_OUTPUT"
    jq '.current_stage = "review"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
    "$REAL_GIT" add -A
    "$REAL_GIT" diff --cached --quiet || "$REAL_GIT" commit -q -m "swarm: skipping visual QA (bugfix)"
  else
    echo "skip_qa=false" >> "$GITHUB_OUTPUT"
  fi
}

run_qa_dryrun_stub() {
  jq '.current_stage = "visual_qa"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
}

run_qa_check() {
  reset_output
  STAGE=$(jq -r '.current_stage' swarm-state.json)
  if [ "$STAGE" = "development" ]; then
    echo "passed=false" >> "$GITHUB_OUTPUT"
  else
    echo "passed=true" >> "$GITHUB_OUTPUT"
    jq '.last_agent = "visual-qa"' \
      swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  fi
  "$REAL_GIT" add -A
  "$REAL_GIT" diff --cached --quiet || "$REAL_GIT" commit -q -m "swarm: visual QA check"
}

run_reviewer_dryrun_stub() {
  jq '.last_agent = "reviewer"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
}

run_post_reviewer_state() {
  jq '.last_agent = "reviewer" | .last_updated = (now | tostring)' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A
  "$REAL_GIT" diff --cached --quiet || "$REAL_GIT" commit -q -m "swarm: review complete"
}

run_update_stage_review() {
  jq '.current_stage = "review"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A
  "$REAL_GIT" diff --cached --quiet || "$REAL_GIT" commit -q -m "swarm: visual QA passed, starting review"
}

# ============================================================
# Discovery Path Tests
# ============================================================

test_discovery_bugfix() {
  setup_test_env

  # Triage → BA → TL (PS+Arch skipped)
  run_init_state 1
  run_human_gate
  assert_eq "bugfix disc: gate open" "$(read_output blocked)" "false"

  run_read_resume_state
  LAST=$(read_output last_agent)
  RESUME=$(read_output resume_agent)

  run_triage 1 "[Bug]: Fix button" ""
  assert_eq "bugfix disc: tier" "$(read_output tier)" "bugfix"

  run_ba_check "$LAST" "$RESUME"
  assert_eq "bugfix disc: BA runs" "$(read_output run)" "true"

  run_ba_dryrun_stub
  run_post_agent_update "business-analyst"
  run_human_gate_check
  assert_eq "bugfix disc: gate after BA" "$(read_output blocked)" "false"

  # PS should be skipped
  run_ps_check "bugfix" "business-analyst" "" "true"
  assert_eq "bugfix disc: PS skipped" "$(read_output run)" "false"

  # Architect should be skipped
  run_arch_check "bugfix" "business-analyst" "" "false" "true"
  assert_eq "bugfix disc: Arch skipped" "$(read_output run)" "false"

  # TL runs
  run_update_stage_planning
  run_tl_dryrun_stub
  run_post_agent_update "tech-lead"

  assert_eq "bugfix disc: final stage" "$(read_state '.current_stage')" "planning"
  assert_eq "bugfix disc: last agent" "$(read_state '.last_agent')" "tech-lead"
  assert_eq "bugfix disc: tier in state" "$(read_state '.issue_tier')" "bugfix"
  assert_eq "bugfix disc: total tasks" "$(read_state '.total_tasks')" "3"

  teardown_test_env
}

test_discovery_enhancement() {
  setup_test_env

  # Triage → BA → Arch → TL (PS skipped)
  run_init_state 2
  run_human_gate
  run_read_resume_state
  LAST=$(read_output last_agent)
  RESUME=$(read_output resume_agent)

  run_triage 2 "Add sorting option" ""
  assert_eq "enh disc: tier (no prefix defaults)" "$(read_output tier)" "feature"

  teardown_test_env

  # Try with swarm-tier label
  setup_test_env
  run_init_state 2
  run_human_gate
  run_read_resume_state
  LAST=$(read_output last_agent)
  RESUME=$(read_output resume_agent)

  run_triage 2 "Add sorting option" "swarm-tier:enhancement"
  assert_eq "enh disc: tier from label" "$(read_output tier)" "enhancement"

  run_ba_check "$LAST" "$RESUME"
  assert_eq "enh disc: BA runs" "$(read_output run)" "true"
  run_ba_dryrun_stub
  run_post_agent_update "business-analyst"
  run_human_gate_check

  run_ps_check "enhancement" "business-analyst" "" "true"
  assert_eq "enh disc: PS skipped" "$(read_output run)" "false"

  run_arch_check "enhancement" "business-analyst" "" "false" "true"
  assert_eq "enh disc: Arch runs" "$(read_output run)" "true"
  run_arch_dryrun_stub
  run_post_agent_update "architect"
  run_human_gate_check

  run_update_stage_planning
  run_tl_dryrun_stub
  run_post_agent_update "tech-lead"

  assert_eq "enh disc: final last_agent" "$(read_state '.last_agent')" "tech-lead"
  assert_eq "enh disc: tier in state" "$(read_state '.issue_tier')" "enhancement"

  teardown_test_env
}

test_discovery_feature() {
  setup_test_env

  # Triage → BA → PS → Arch → TL (all agents)
  run_init_state 3
  run_human_gate
  run_read_resume_state
  LAST=$(read_output last_agent)
  RESUME=$(read_output resume_agent)

  run_triage 3 "[Feature]: Add dashboard" ""
  assert_eq "feat disc: tier" "$(read_output tier)" "feature"

  run_ba_check "$LAST" "$RESUME"
  assert_eq "feat disc: BA runs" "$(read_output run)" "true"
  run_ba_dryrun_stub
  run_post_agent_update "business-analyst"
  run_human_gate_check

  run_ps_check "feature" "business-analyst" "" "true"
  assert_eq "feat disc: PS runs" "$(read_output run)" "true"
  run_ps_dryrun_stub
  run_post_agent_update "product-strategist"
  run_human_gate_check

  run_arch_check "feature" "product-strategist" "" "true" "false"
  assert_eq "feat disc: Arch runs" "$(read_output run)" "true"
  run_arch_dryrun_stub
  run_post_agent_update "architect"
  run_human_gate_check

  run_update_stage_planning
  run_tl_dryrun_stub
  run_post_agent_update "tech-lead"

  assert_eq "feat disc: final last_agent" "$(read_state '.last_agent')" "tech-lead"
  assert_eq "feat disc: tier in state" "$(read_state '.issue_tier')" "feature"
  assert_eq "feat disc: plan exists" "$(test -f docs/plan.md && echo yes)" "yes"
  assert_eq "feat disc: product-spec exists" "$(test -f docs/product-spec.md && echo yes)" "yes"

  teardown_test_env
}

test_discovery_manual_override() {
  setup_test_env

  # swarm-tier:bugfix label should override [Feature]: title prefix
  run_init_state 4
  run_human_gate
  run_read_resume_state

  run_triage 4 "[Feature]: Big new thing" "swarm-tier:bugfix"
  assert_eq "override: label beats title" "$(read_output tier)" "bugfix"

  teardown_test_env
}

test_discovery_resume_keeps_tier() {
  setup_test_env

  # Pre-set tier in state → triage should keep it
  jq '.issue_tier = "enhancement"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  run_init_state 5
  run_human_gate
  run_read_resume_state

  run_triage 5 "[Feature]: Something" "swarm-tier:feature"
  assert_eq "resume: keeps existing tier" "$(read_output tier)" "enhancement"

  teardown_test_env
}

test_discovery_human_gate_blocks() {
  setup_test_env

  # Init state first (sets human_input_needed=false), then override to true
  run_init_state 6
  jq '.human_input_needed = true' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  run_human_gate
  assert_eq "human gate: blocks" "$(read_output blocked)" "true"

  teardown_test_env
}

# ============================================================
# Build Path Tests
# ============================================================

test_build_bugfix_skip_qa() {
  setup_test_env

  # Setup: bugfix tier, requires_visual_qa=false, planning stage
  jq '.issue_tier = "bugfix" | .requires_visual_qa = false | .current_stage = "planning" | .status = "active" | .total_tasks = 3' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A && "$REAL_GIT" commit -q -m "setup"

  run_build_state_update
  BUILD_STAGE=$(read_output stage)
  assert_eq "bugfix build: stage=development" "$BUILD_STAGE" "development"

  # Dev dry-run stub
  run_dev_dryrun_stub
  run_post_dev_state
  TASKS_DONE=$(read_output tasks_done)
  assert_eq "bugfix build: tasks done" "$TASKS_DONE" "true"

  # QA skip check
  run_qa_needed_check
  assert_eq "bugfix build: QA skipped" "$(read_output skip_qa)" "true"
  assert_eq "bugfix build: stage after qa skip" "$(read_state '.current_stage')" "review"

  # Reviewer
  run_update_stage_review
  run_reviewer_dryrun_stub
  run_post_reviewer_state
  assert_eq "bugfix build: last agent" "$(read_state '.last_agent')" "reviewer"

  teardown_test_env
}

test_build_bugfix_with_qa() {
  setup_test_env

  # Setup: bugfix tier, requires_visual_qa=true
  jq '.issue_tier = "bugfix" | .requires_visual_qa = true | .current_stage = "planning" | .status = "active" | .total_tasks = 2' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A && "$REAL_GIT" commit -q -m "setup"

  run_build_state_update
  run_dev_dryrun_stub
  run_post_dev_state

  run_qa_needed_check
  assert_eq "bugfix+qa: QA not skipped" "$(read_output skip_qa)" "false"

  # QA runs and passes
  run_qa_dryrun_stub
  run_qa_check
  assert_eq "bugfix+qa: QA passed" "$(read_output passed)" "true"

  run_update_stage_review
  run_reviewer_dryrun_stub
  run_post_reviewer_state
  assert_eq "bugfix+qa: last agent" "$(read_state '.last_agent')" "reviewer"

  teardown_test_env
}

test_build_feature_full() {
  setup_test_env

  # Setup: feature tier, full pipeline
  jq '.issue_tier = "feature" | .requires_visual_qa = true | .current_stage = "planning" | .status = "active" | .total_tasks = 5' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A && "$REAL_GIT" commit -q -m "setup"

  run_build_state_update
  assert_eq "feat build: stage" "$(read_output stage)" "development"

  run_dev_dryrun_stub
  run_post_dev_state
  assert_eq "feat build: tasks done" "$(read_output tasks_done)" "true"

  run_qa_needed_check
  assert_eq "feat build: QA not skipped" "$(read_output skip_qa)" "false"

  run_qa_dryrun_stub
  run_qa_check
  assert_eq "feat build: QA passed" "$(read_output passed)" "true"

  run_update_stage_review
  run_reviewer_dryrun_stub
  run_post_reviewer_state

  assert_eq "feat build: final stage" "$(read_state '.current_stage')" "review"
  assert_eq "feat build: last agent" "$(read_state '.last_agent')" "reviewer"

  teardown_test_env
}

test_build_resume_from_review() {
  setup_test_env

  # Setup: already at review stage
  jq '.issue_tier = "feature" | .current_stage = "review" | .status = "active"' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A && "$REAL_GIT" commit -q -m "setup"

  run_build_state_update
  BUILD_STAGE=$(read_output stage)
  assert_eq "resume review: stage stays review" "$BUILD_STAGE" "review"

  # Dev should NOT run (stage != development)
  assert_eq "resume review: dev skipped" "$([[ "$BUILD_STAGE" == "development" ]] && echo yes || echo no)" "no"

  # Reviewer runs directly
  run_reviewer_dryrun_stub
  run_post_reviewer_state
  assert_eq "resume review: last agent" "$(read_state '.last_agent')" "reviewer"

  teardown_test_env
}

test_build_qa_failure_gate() {
  setup_test_env

  # Setup: feature with 0 tasks (edge case — dev completes immediately)
  jq '.issue_tier = "feature" | .requires_visual_qa = true | .current_stage = "planning" | .status = "active" | .total_tasks = 0' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" add -A && "$REAL_GIT" commit -q -m "setup"

  run_build_state_update
  run_dev_dryrun_stub
  run_post_dev_state
  run_qa_needed_check

  # Simulate 3 QA failures by setting stage back to development before each check
  jq '.current_stage = "development"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  run_qa_check
  QA1_PASSED=$(read_output passed)
  assert_eq "qa gate: cycle 1 failed" "$QA1_PASSED" "false"

  jq '.current_stage = "development"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  run_qa_check
  QA2_PASSED=$(read_output passed)
  assert_eq "qa gate: cycle 2 failed" "$QA2_PASSED" "false"

  jq '.current_stage = "development"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  run_qa_check
  QA3_PASSED=$(read_output passed)
  assert_eq "qa gate: cycle 3 failed" "$QA3_PASSED" "false"

  # QA failure gate fires when all 3 fail
  SKIP_QA="false"
  STAGE=$(read_state '.current_stage')
  POST_DEV_TASKS_DONE="true"
  QA_GATE="false"
  if [ "$STAGE" != "review" ] && [ "$POST_DEV_TASKS_DONE" != "false" ] && [ "$SKIP_QA" != "true" ] && \
     [ "$QA1_PASSED" = "false" ] && [ "$QA2_PASSED" = "false" ] && [ "$QA3_PASSED" = "false" ]; then
    QA_GATE="true"
  fi
  assert_eq "qa gate: fires after 3 failures" "$QA_GATE" "true"

  teardown_test_env
}

# ============================================================
# State Management Tests
# ============================================================

test_state_tier_written() {
  setup_test_env

  run_init_state 10
  run_human_gate
  run_read_resume_state
  run_triage 10 "[Bug]: Crash on load" ""

  assert_eq "state tier: written to state" "$(read_state '.issue_tier')" "bugfix"

  teardown_test_env
}

test_state_agent_tracking() {
  setup_test_env

  run_init_state 11
  run_ba_dryrun_stub
  assert_eq "agent tracking: BA" "$(read_state '.last_agent')" "business-analyst"

  run_ps_dryrun_stub
  assert_eq "agent tracking: PS" "$(read_state '.last_agent')" "product-strategist"

  run_arch_dryrun_stub
  assert_eq "agent tracking: Arch" "$(read_state '.last_agent')" "architect"

  run_tl_dryrun_stub
  assert_eq "agent tracking: TL" "$(read_state '.last_agent')" "tech-lead"

  teardown_test_env
}

test_state_stage_progression() {
  setup_test_env

  # Start from idle
  assert_eq "stage prog: starts idle" "$(read_state '.current_stage')" "idle"

  # Init → discovery
  run_init_state 12
  assert_eq "stage prog: init → discovery" "$(read_state '.current_stage')" "discovery"

  # Discovery → planning
  run_update_stage_planning
  assert_eq "stage prog: → planning" "$(read_state '.current_stage')" "planning"

  # Planning → development (via build state update)
  run_build_state_update
  assert_eq "stage prog: → development" "$(read_state '.current_stage')" "development"

  # Development → visual_qa (via post-dev)
  jq '.total_tasks = 0' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  run_dev_dryrun_stub
  run_post_dev_state
  assert_eq "stage prog: → visual_qa" "$(read_state '.current_stage')" "visual_qa"

  # visual_qa → review
  run_update_stage_review
  assert_eq "stage prog: → review" "$(read_state '.current_stage')" "review"

  teardown_test_env
}

# ============================================================
# GitHub Integration Tests
# ============================================================

test_gh_open_draft_pr_skips_existing() {
  setup_test_env

  # Override mock to return an existing PR number (simulates: gh pr list --json number -q '.[0].number')
  cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/bin/bash
echo "$@" >> "$MOCK_GH_LOG"
case "$1 $2" in
  "pr list")   echo "42" ;;
  "pr create") echo "https://github.com/test/repo/pull/42" ;;
  *)           echo "ok" ;;
esac
MOCK_GH
  chmod +x "$MOCK_DIR/gh"

  # Set up state for gh_open_draft_pr
  jq '.current_issue = 1 | .tasks = [{"title":"Test task"}]' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" checkout -b swarm/issue-1 2>/dev/null || true

  source scripts/github-integration.sh 2>/dev/null || true
  gh_open_draft_pr

  # Should NOT have called pr create
  if grep -q "pr create" "$MOCK_GH_LOG"; then
    PR_CREATED="true"
  else
    PR_CREATED="false"
  fi
  assert_eq "pr skip existing: no create call" "$PR_CREATED" "false"

  teardown_test_env
}

test_gh_open_draft_pr_creates_new() {
  setup_test_env

  # Mock returns empty string for pr list (simulates: gh pr list --json number -q '.[0].number' with no results)
  cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/bin/bash
echo "$@" >> "$MOCK_GH_LOG"
case "$1 $2" in
  "pr list")   echo "" ;;
  "pr create") echo "https://github.com/test/repo/pull/1" ;;
  *)           echo "ok" ;;
esac
MOCK_GH
  chmod +x "$MOCK_DIR/gh"

  jq '.current_issue = 1 | .tasks = [{"title":"Test task"}]' \
    swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" checkout -b swarm/issue-1 2>/dev/null || true

  source scripts/github-integration.sh 2>/dev/null || true
  gh_open_draft_pr

  if grep -q "pr create" "$MOCK_GH_LOG"; then
    PR_CREATED="true"
  else
    PR_CREATED="false"
  fi
  assert_eq "pr create new: create called" "$PR_CREATED" "true"

  teardown_test_env
}

test_gh_mark_pr_ready() {
  setup_test_env

  cat > "$MOCK_DIR/gh" << 'MOCK_GH'
#!/bin/bash
echo "$@" >> "$MOCK_GH_LOG"
case "$1 $2" in
  "pr list")  echo "7" ;;
  "pr ready") echo "ok" ;;
  *)          echo "ok" ;;
esac
MOCK_GH
  chmod +x "$MOCK_DIR/gh"

  jq '.current_issue = 1' swarm-state.json > tmp.json && mv tmp.json swarm-state.json
  "$REAL_GIT" checkout -b swarm/issue-1 2>/dev/null || true

  source scripts/github-integration.sh 2>/dev/null || true
  gh_mark_pr_ready

  if grep -q "pr ready" "$MOCK_GH_LOG"; then
    PR_READY="true"
  else
    PR_READY="false"
  fi
  assert_eq "mark pr ready: ready called" "$PR_READY" "true"

  teardown_test_env
}

# ============================================================
# Runner
# ============================================================

echo "=== Integration Tests ==="
echo ""

echo "--- Discovery: Bugfix Path ---"
test_discovery_bugfix

echo "--- Discovery: Enhancement Path ---"
test_discovery_enhancement

echo "--- Discovery: Feature Path ---"
test_discovery_feature

echo "--- Discovery: Manual Override ---"
test_discovery_manual_override

echo "--- Discovery: Resume Keeps Tier ---"
test_discovery_resume_keeps_tier

echo "--- Discovery: Human Gate Blocks ---"
test_discovery_human_gate_blocks

echo ""
echo "--- Build: Bugfix Skip QA ---"
test_build_bugfix_skip_qa

echo "--- Build: Bugfix With QA ---"
test_build_bugfix_with_qa

echo "--- Build: Feature Full ---"
test_build_feature_full

echo "--- Build: Resume From Review ---"
test_build_resume_from_review

echo "--- Build: QA Failure Gate ---"
test_build_qa_failure_gate

echo ""
echo "--- State: Tier Written ---"
test_state_tier_written

echo "--- State: Agent Tracking ---"
test_state_agent_tracking

echo "--- State: Stage Progression ---"
test_state_stage_progression

echo ""
echo "--- GitHub: PR Skip Existing ---"
test_gh_open_draft_pr_skips_existing

echo "--- GitHub: PR Create New ---"
test_gh_open_draft_pr_creates_new

echo "--- GitHub: Mark PR Ready ---"
test_gh_mark_pr_ready

echo ""
echo "=== Results ==="
for t in "${TESTS[@]}"; do echo "$t"; done
echo ""
echo "Total: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
