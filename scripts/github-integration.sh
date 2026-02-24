#!/bin/bash
# github-integration.sh — GitHub API helpers for the swarm
# Sourced by workflow steps and available to agents
# Requires: gh CLI authenticated

set -euo pipefail

STATE_FILE="swarm-state.json"

# Get repo and issue from state
get_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    echo "$GITHUB_REPOSITORY"
  else
    grep '^repo:' .swarm/config.yaml | sed 's/^repo:[[:space:]]*//' | tr -d "\"'"
  fi
}

get_issue_number() {
  jq -r '.current_issue' "$STATE_FILE"
}

# --- Issue Comments ---

gh_post_issue_comment() {
  local body="$1"
  local repo=$(get_repo)
  local issue=$(get_issue_number)

  gh issue comment "$issue" --repo "$repo" --body "$body"
  echo "[GH] Posted comment on issue #$issue"
}

gh_read_issue_comments() {
  local repo=$(get_repo)
  local issue=$(get_issue_number)

  gh issue view "$issue" --repo "$repo" --comments --json comments \
    | jq -r '.comments[] | "[\(.author.login) at \(.createdAt)]:\n\(.body)\n---"'
}

gh_read_issue_body() {
  local repo=$(get_repo)
  local issue=$(get_issue_number)

  gh issue view "$issue" --repo "$repo" --json body | jq -r '.body'
}

# --- Labels ---

gh_add_label() {
  local label="$1"
  local repo=$(get_repo)
  local issue=$(get_issue_number)

  gh issue edit "$issue" --repo "$repo" --add-label "$label"
  echo "[GH] Added label '$label' to issue #$issue"
}

gh_remove_label() {
  local label="$1"
  local repo=$(get_repo)
  local issue=$(get_issue_number)

  gh issue edit "$issue" --repo "$repo" --remove-label "$label"
  echo "[GH] Removed label '$label' from issue #$issue"
}

# --- Pull Requests ---

_require_pr_number() {
  local repo=$(get_repo)
  local pr_number
  pr_number=$(gh pr list --repo "$repo" --head "$(git branch --show-current)" --json number -q '.[0].number')
  if [ -z "$pr_number" ] || [ "$pr_number" = "null" ]; then
    echo "[GH] ERROR: No PR found for branch $(git branch --show-current)" >&2
    return 1
  fi
  echo "$pr_number"
}

gh_open_draft_pr() {
  local repo=$(get_repo)
  local issue=$(get_issue_number)
  local branch=$(git branch --show-current)

  local title="[Swarm] Issue #${issue}: $(jq -r '.tasks[0].title // "Implementation"' "$STATE_FILE")"

  local body="## 🤖 Automated PR — Issue #${issue}

### Plan
See \`docs/plan.md\` for the full implementation plan.

### Status
- [ ] Plan approved by stakeholder
- [ ] Implementation complete
- [ ] Visual QA passed
- [ ] Tech review complete

### Preview
Vercel preview will be available once implementation begins.

---
*This PR was created by the swarm. Review the plan and approve by commenting \`/approve-plan\` on this PR.*"

  gh pr create --repo "$repo" \
    --base main \
    --head "$branch" \
    --title "$title" \
    --body "$body" \
    --draft

  echo "[GH] Draft PR created for issue #$issue"
}

gh_update_pr_body() {
  local new_body="$1"
  local repo=$(get_repo)
  local pr_number
  pr_number=$(_require_pr_number) || return 1

  gh pr edit "$pr_number" --repo "$repo" --body "$new_body"
  echo "[GH] Updated PR #$pr_number body"
}

gh_post_pr_comment() {
  local body="$1"
  local repo=$(get_repo)
  local pr_number
  pr_number=$(_require_pr_number) || return 1

  gh pr comment "$pr_number" --repo "$repo" --body "$body"
  echo "[GH] Posted comment on PR #$pr_number"
}

gh_mark_pr_ready() {
  local repo=$(get_repo)
  local pr_number
  pr_number=$(_require_pr_number) || return 1

  gh pr ready "$pr_number" --repo "$repo"
  echo "[GH] PR #$pr_number marked ready for review"
}

# --- Project Board ---

gh_move_issue_to_column() {
  local column="$1"
  # GitHub Projects v2 uses graphql — simplified version using labels as proxy
  case "$column" in
    "in-progress")
      gh_add_label "swarm-working"
      gh_remove_label "ready-to-build" 2>/dev/null || true
      ;;
    "review")
      gh_add_label "swarm-review"
      gh_remove_label "swarm-working" 2>/dev/null || true
      ;;
    "done")
      gh_add_label "swarm-complete"
      gh_remove_label "swarm-review" 2>/dev/null || true
      ;;
  esac
  echo "[GH] Issue moved to '$column'"
}
