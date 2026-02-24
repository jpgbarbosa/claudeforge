#!/bin/bash
# test-triage-logic.sh — Test the triage/tier logic added to workflows
# Run: ./tests/test-triage-logic.sh

set -euo pipefail

PASS=0
FAIL=0
TESTS=()

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

setup() {
  TEST_DIR=$(mktemp -d)
  cp swarm-state.json "$TEST_DIR/swarm-state.json"
  cd "$TEST_DIR"
}

teardown() {
  cd - > /dev/null
  rm -rf "$TEST_DIR"
}

# ==========================================================
# Triage: tier detection from state
# ==========================================================

test_triage_null_tier_defaults_to_feature() {
  setup
  jq '.issue_tier = null' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  EXISTING_TIER=$(jq -r '.issue_tier // ""' swarm-state.json)
  if [ -n "$EXISTING_TIER" ] && [ "$EXISTING_TIER" != "null" ]; then
    TIER="$EXISTING_TIER"
  else
    TIER="feature"
  fi
  assert_eq "null tier defaults to feature" "$TIER" "feature"
  teardown
}

test_triage_keeps_existing_tier_on_resume() {
  setup
  jq '.issue_tier = "bugfix"' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  EXISTING_TIER=$(jq -r '.issue_tier // ""' swarm-state.json)
  if [ -n "$EXISTING_TIER" ] && [ "$EXISTING_TIER" != "null" ]; then
    TIER="$EXISTING_TIER"
  else
    TIER="feature"
  fi
  assert_eq "keeps existing tier on resume" "$TIER" "bugfix"
  teardown
}

# ==========================================================
# PS check with tier
# ==========================================================

test_ps_skipped_for_bugfix() {
  TIER="bugfix"; BA_RAN="true"; LAST=""; RESUME=""
  if [ "$TIER" != "feature" ]; then PS_RUN="false"
  elif [ "$BA_RAN" = "true" ] || [ "$RESUME" = "product-strategist" ] || [ "$LAST" = "business-analyst" ]; then PS_RUN="true"
  else PS_RUN="false"; fi
  assert_eq "bugfix: PS skipped" "$PS_RUN" "false"
}

test_ps_skipped_for_enhancement() {
  TIER="enhancement"; BA_RAN="true"; LAST=""; RESUME=""
  if [ "$TIER" != "feature" ]; then PS_RUN="false"
  elif [ "$BA_RAN" = "true" ] || [ "$RESUME" = "product-strategist" ] || [ "$LAST" = "business-analyst" ]; then PS_RUN="true"
  else PS_RUN="false"; fi
  assert_eq "enhancement: PS skipped" "$PS_RUN" "false"
}

test_ps_runs_for_feature() {
  TIER="feature"; BA_RAN="true"; LAST=""; RESUME=""
  if [ "$TIER" != "feature" ]; then PS_RUN="false"
  elif [ "$BA_RAN" = "true" ] || [ "$RESUME" = "product-strategist" ] || [ "$LAST" = "business-analyst" ]; then PS_RUN="true"
  else PS_RUN="false"; fi
  assert_eq "feature: PS runs" "$PS_RUN" "true"
}

# ==========================================================
# Architect check with tier
# ==========================================================

test_architect_skipped_for_bugfix() {
  TIER="bugfix"; BA_RAN="true"; PS_RAN="false"; LAST=""; RESUME=""
  if [ "$TIER" = "bugfix" ]; then ARCH_RUN="false"
  elif [ "$TIER" = "enhancement" ] && { [ "$BA_RAN" = "true" ] || [ "$LAST" = "business-analyst" ]; }; then ARCH_RUN="true"
  elif [ "$PS_RAN" = "true" ] || [ "$RESUME" = "architect" ] || [ "$LAST" = "product-strategist" ]; then ARCH_RUN="true"
  else ARCH_RUN="false"; fi
  assert_eq "bugfix: Architect skipped" "$ARCH_RUN" "false"
}

test_architect_runs_for_enhancement_after_ba() {
  TIER="enhancement"; BA_RAN="true"; PS_RAN="false"; LAST=""; RESUME=""
  if [ "$TIER" = "bugfix" ]; then ARCH_RUN="false"
  elif [ "$TIER" = "enhancement" ] && { [ "$BA_RAN" = "true" ] || [ "$LAST" = "business-analyst" ]; }; then ARCH_RUN="true"
  elif [ "$PS_RAN" = "true" ] || [ "$RESUME" = "architect" ] || [ "$LAST" = "product-strategist" ]; then ARCH_RUN="true"
  else ARCH_RUN="false"; fi
  assert_eq "enhancement: Architect runs after BA" "$ARCH_RUN" "true"
}

test_architect_runs_for_feature_after_ps() {
  TIER="feature"; BA_RAN="false"; PS_RAN="true"; LAST="product-strategist"; RESUME=""
  if [ "$TIER" = "bugfix" ]; then ARCH_RUN="false"
  elif [ "$TIER" = "enhancement" ] && { [ "$BA_RAN" = "true" ] || [ "$LAST" = "business-analyst" ]; }; then ARCH_RUN="true"
  elif [ "$PS_RAN" = "true" ] || [ "$RESUME" = "architect" ] || [ "$LAST" = "product-strategist" ]; then ARCH_RUN="true"
  else ARCH_RUN="false"; fi
  assert_eq "feature: Architect runs after PS" "$ARCH_RUN" "true"
}

test_architect_runs_for_enhancement_resume() {
  TIER="enhancement"; BA_RAN="false"; PS_RAN="false"; LAST="business-analyst"; RESUME=""
  if [ "$TIER" = "bugfix" ]; then ARCH_RUN="false"
  elif [ "$TIER" = "enhancement" ] && { [ "$BA_RAN" = "true" ] || [ "$LAST" = "business-analyst" ]; }; then ARCH_RUN="true"
  elif [ "$PS_RAN" = "true" ] || [ "$RESUME" = "architect" ] || [ "$LAST" = "product-strategist" ]; then ARCH_RUN="true"
  else ARCH_RUN="false"; fi
  assert_eq "enhancement resume: Architect runs from last=BA" "$ARCH_RUN" "true"
}

test_architect_resume_with_resume_agent() {
  TIER="feature"; BA_RAN="false"; PS_RAN="false"; LAST="architect"; RESUME="architect"
  if [ "$TIER" = "bugfix" ]; then ARCH_RUN="false"
  elif [ "$TIER" = "enhancement" ] && { [ "$BA_RAN" = "true" ] || [ "$LAST" = "business-analyst" ]; }; then ARCH_RUN="true"
  elif [ "$PS_RAN" = "true" ] || [ "$RESUME" = "architect" ] || [ "$LAST" = "product-strategist" ]; then ARCH_RUN="true"
  else ARCH_RUN="false"; fi
  assert_eq "resume architect: Architect re-runs" "$ARCH_RUN" "true"
}

# ==========================================================
# QA skip logic
# ==========================================================

test_qa_skip_bugfix_no_frontend() {
  setup
  jq '.issue_tier = "bugfix" | .requires_visual_qa = false' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  TIER=$(jq -r '.issue_tier // "feature"' swarm-state.json)
  REQ=$(jq -r '.requires_visual_qa' swarm-state.json)
  if [ "$REQ" = "null" ]; then REQ="true"; fi
  if [ "$TIER" = "bugfix" ] && [ "$REQ" = "false" ]; then SKIP_QA="true"; else SKIP_QA="false"; fi
  assert_eq "bugfix+no frontend: QA skipped" "$SKIP_QA" "true"
  teardown
}

test_qa_runs_bugfix_with_frontend() {
  setup
  jq '.issue_tier = "bugfix" | .requires_visual_qa = true' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  TIER=$(jq -r '.issue_tier // "feature"' swarm-state.json)
  REQ=$(jq -r '.requires_visual_qa' swarm-state.json)
  if [ "$REQ" = "null" ]; then REQ="true"; fi
  if [ "$TIER" = "bugfix" ] && [ "$REQ" = "false" ]; then SKIP_QA="true"; else SKIP_QA="false"; fi
  assert_eq "bugfix+frontend: QA runs" "$SKIP_QA" "false"
  teardown
}

test_qa_always_runs_for_feature() {
  setup
  jq '.issue_tier = "feature" | .requires_visual_qa = false' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  TIER=$(jq -r '.issue_tier // "feature"' swarm-state.json)
  REQ=$(jq -r '.requires_visual_qa' swarm-state.json)
  if [ "$REQ" = "null" ]; then REQ="true"; fi
  if [ "$TIER" = "bugfix" ] && [ "$REQ" = "false" ]; then SKIP_QA="true"; else SKIP_QA="false"; fi
  assert_eq "feature: QA always runs" "$SKIP_QA" "false"
  teardown
}

test_qa_always_runs_for_enhancement() {
  setup
  jq '.issue_tier = "enhancement" | .requires_visual_qa = false' swarm-state.json > tmp.json && mv tmp.json swarm-state.json

  TIER=$(jq -r '.issue_tier // "feature"' swarm-state.json)
  REQ=$(jq -r '.requires_visual_qa' swarm-state.json)
  if [ "$REQ" = "null" ]; then REQ="true"; fi
  if [ "$TIER" = "bugfix" ] && [ "$REQ" = "false" ]; then SKIP_QA="true"; else SKIP_QA="false"; fi
  assert_eq "enhancement: QA always runs" "$SKIP_QA" "false"
  teardown
}

# ==========================================================
# Reviewer trigger with skip_qa
# ==========================================================

test_reviewer_triggers_when_qa_skipped() {
  STAGE="development"; SKIP_QA="true"; QA1_PASSED=""; QA2_PASSED=""; QA3_PASSED=""
  REVIEWER_RUNS="false"
  if [ "$STAGE" = "review" ] || [ "$SKIP_QA" = "true" ] || [ "$QA1_PASSED" = "true" ] || [ "$QA2_PASSED" = "true" ] || [ "$QA3_PASSED" = "true" ]; then
    REVIEWER_RUNS="true"
  fi
  assert_eq "QA skipped: Reviewer runs" "$REVIEWER_RUNS" "true"
}

test_reviewer_waits_normally() {
  STAGE="development"; SKIP_QA="false"; QA1_PASSED=""; QA2_PASSED=""; QA3_PASSED=""
  REVIEWER_RUNS="false"
  if [ "$STAGE" = "review" ] || [ "$SKIP_QA" = "true" ] || [ "$QA1_PASSED" = "true" ] || [ "$QA2_PASSED" = "true" ] || [ "$QA3_PASSED" = "true" ]; then
    REVIEWER_RUNS="true"
  fi
  assert_eq "normal: Reviewer waits for QA" "$REVIEWER_RUNS" "false"
}

# ==========================================================
# QA failure gate with skip_qa
# ==========================================================

test_qa_failure_gate_skipped_when_qa_skipped() {
  STAGE="development"; SKIP_QA="true"; POST_DEV_TASKS_DONE="true"
  QA1_PASSED=""; QA2_PASSED=""; QA3_PASSED=""
  QA_GATE="false"
  if [ "$STAGE" != "review" ] && [ "$POST_DEV_TASKS_DONE" != "false" ] && [ "$SKIP_QA" != "true" ] && [ "$QA1_PASSED" = "false" ] && [ "$QA2_PASSED" = "false" ] && [ "$QA3_PASSED" = "false" ]; then
    QA_GATE="true"
  fi
  assert_eq "QA skipped: failure gate does NOT fire" "$QA_GATE" "false"
}

# ==========================================================
# Full pipeline path tests
# ==========================================================

test_bugfix_full_path() {
  TIER="bugfix"; LAST=""; RESUME=""
  if [ -z "$LAST" ] || [ "$LAST" = "null" ]; then BA_RUN="true"; else BA_RUN="false"; fi
  if [ "$TIER" != "feature" ]; then PS_RUN="false"; else PS_RUN="true"; fi
  if [ "$TIER" = "bugfix" ]; then ARCH_RUN="false"; else ARCH_RUN="true"; fi
  assert_eq "bugfix path: BA=true, PS=false, Arch=false" "${BA_RUN},${PS_RUN},${ARCH_RUN}" "true,false,false"
}

test_enhancement_full_path() {
  TIER="enhancement"; LAST=""
  if [ -z "$LAST" ] || [ "$LAST" = "null" ]; then BA_RUN="true"; else BA_RUN="false"; fi
  if [ "$TIER" != "feature" ]; then PS_RUN="false"; else PS_RUN="true"; fi
  BA_RAN="$BA_RUN"
  if [ "$TIER" = "bugfix" ]; then ARCH_RUN="false"
  elif [ "$TIER" = "enhancement" ] && { [ "$BA_RAN" = "true" ] || [ "$LAST" = "business-analyst" ]; }; then ARCH_RUN="true"
  else ARCH_RUN="false"; fi
  assert_eq "enhancement path: BA=true, PS=false, Arch=true" "${BA_RUN},${PS_RUN},${ARCH_RUN}" "true,false,true"
}

test_feature_full_path() {
  TIER="feature"; LAST=""
  if [ -z "$LAST" ] || [ "$LAST" = "null" ]; then BA_RUN="true"; else BA_RUN="false"; fi
  if [ "$TIER" != "feature" ]; then PS_RUN="false"
  elif [ "$BA_RUN" = "true" ]; then PS_RUN="true"
  else PS_RUN="false"; fi
  if [ "$TIER" = "bugfix" ]; then ARCH_RUN="false"
  elif [ "$PS_RUN" = "true" ]; then ARCH_RUN="true"
  else ARCH_RUN="false"; fi
  assert_eq "feature path: BA=true, PS=true, Arch=true" "${BA_RUN},${PS_RUN},${ARCH_RUN}" "true,true,true"
}

# ==========================================================
# Run all tests
# ==========================================================

echo "=== Triage Logic Tests ==="
echo ""

echo "--- Triage: Tier Detection ---"
test_triage_null_tier_defaults_to_feature
test_triage_keeps_existing_tier_on_resume

echo ""
echo "--- Discovery: PS Check with Tier ---"
test_ps_skipped_for_bugfix
test_ps_skipped_for_enhancement
test_ps_runs_for_feature

echo ""
echo "--- Discovery: Architect Check with Tier ---"
test_architect_skipped_for_bugfix
test_architect_runs_for_enhancement_after_ba
test_architect_runs_for_feature_after_ps
test_architect_runs_for_enhancement_resume
test_architect_resume_with_resume_agent

echo ""
echo "--- Build: QA Skip Logic ---"
test_qa_skip_bugfix_no_frontend
test_qa_runs_bugfix_with_frontend
test_qa_always_runs_for_feature
test_qa_always_runs_for_enhancement

echo ""
echo "--- Build: Reviewer Trigger ---"
test_reviewer_triggers_when_qa_skipped
test_reviewer_waits_normally

echo ""
echo "--- Build: QA Failure Gate ---"
test_qa_failure_gate_skipped_when_qa_skipped

echo ""
echo "--- Full Pipeline Paths ---"
test_bugfix_full_path
test_enhancement_full_path
test_feature_full_path

echo ""
echo "=== Results ==="
for t in "${TESTS[@]}"; do echo "$t"; done
echo ""
echo "Total: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
