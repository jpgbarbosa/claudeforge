#!/bin/bash
# integrate.sh — Add the swarm to an existing project
# Usage: ./scripts/integrate.sh /path/to/existing-project
# Run from the claudeforge template directory

set -euo pipefail

TARGET="${1:?Usage: ./scripts/integrate.sh /path/to/existing-project}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -d "$TARGET/.git" ]; then
  echo "ERROR: $TARGET is not a git repository."
  exit 1
fi

echo "Integrating swarm into: $TARGET"
echo ""

# Check for conflicts
CONFLICTS=()
[ -d "$TARGET/.swarm" ] && CONFLICTS+=(".swarm/")
[ -f "$TARGET/swarm-state.json" ] && CONFLICTS+=("swarm-state.json")
[ -d "$TARGET/.github/workflows" ] && [ -f "$TARGET/.github/workflows/swarm-discovery.yaml" ] && CONFLICTS+=(".github/workflows/swarm-*.yaml")

if [ ${#CONFLICTS[@]} -gt 0 ]; then
  echo "Warning: The following already exist in the target project:"
  for c in "${CONFLICTS[@]}"; do echo "   - $c"; done
  echo ""
  read -p "Overwrite? (y/N) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# Copy swarm core
echo "-> Copying .swarm/ (config + agent prompts)"
cp -r "$TEMPLATE_DIR/.swarm" "$TARGET/"

echo "-> Copying scripts/"
mkdir -p "$TARGET/scripts"
cp "$TEMPLATE_DIR/scripts/github-integration.sh" "$TARGET/scripts/"
chmod +x "$TARGET/scripts/"*.sh

echo "-> Copying CLAUDE.md"
cp "$TEMPLATE_DIR/CLAUDE.md" "$TARGET/"

echo "-> Copying GitHub workflows and issue templates"
mkdir -p "$TARGET/.github/workflows"
mkdir -p "$TARGET/.github/ISSUE_TEMPLATE"
cp "$TEMPLATE_DIR/.github/workflows/"*.yaml "$TARGET/.github/workflows/"
cp "$TEMPLATE_DIR/.github/ISSUE_TEMPLATE/"*.yaml "$TARGET/.github/ISSUE_TEMPLATE/"

echo "-> Copying swarm-state.json"
cp "$TEMPLATE_DIR/swarm-state.json" "$TARGET/"

echo "-> Copying docs"
mkdir -p "$TARGET/docs"
cp "$TEMPLATE_DIR/docs/stakeholder-guide.md" "$TARGET/docs/"
cp "$TEMPLATE_DIR/docs/architecture.md" "$TARGET/docs/"

# Create project-context.md if it doesn't exist
if [ ! -f "$TARGET/docs/project-context.md" ]; then
  echo "-> Creating docs/project-context.md (template — you need to fill this in)"
  cp "$TEMPLATE_DIR/docs/project-context.md" "$TARGET/docs/"
else
  echo "-> docs/project-context.md already exists, skipping"
fi

# Append to .gitignore if needed
if [ -f "$TARGET/.gitignore" ]; then
  ADDITIONS=()
  grep -q ".swarm/logs/\*.log" "$TARGET/.gitignore" || ADDITIONS+=(".swarm/logs/*.log")
  grep -q "docs/screenshots/" "$TARGET/.gitignore" || ADDITIONS+=("docs/screenshots/")

  if [ ${#ADDITIONS[@]} -gt 0 ]; then
    echo "-> Appending to .gitignore"
    echo "" >> "$TARGET/.gitignore"
    echo "# Swarm" >> "$TARGET/.gitignore"
    for a in "${ADDITIONS[@]}"; do echo "$a" >> "$TARGET/.gitignore"; done
  fi
else
  echo "-> Creating .gitignore"
  cp "$TEMPLATE_DIR/.gitignore" "$TARGET/"
fi

echo ""
echo "Swarm integrated into $TARGET"
echo ""
echo "Next steps:"
echo ""
echo "  1. Fill in docs/project-context.md with your project's details"
echo "     This is critical — agents use it to understand your existing codebase."
echo ""
echo "  2. Update .swarm/config.yaml:"
echo "     - project_name"
echo "     - repo (e.g., your-org/your-project)"
echo "     - stack settings (framework, runtime, etc.)"
echo ""
echo "  3. Set GitHub repo secrets:"
echo "     - ANTHROPIC_API_KEY"
echo "     - SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY"
echo ""
echo "  4. Commit and push:"
echo "     cd $TARGET"
echo "     git add -A"
echo "     git commit -m 'chore: integrate swarm agent pipeline'"
echo "     git push"
echo ""
echo "  5. Invite stakeholders and point them to docs/stakeholder-guide.md"
