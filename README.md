# Swarm Template

Autonomous multi-agent development pipeline. Stakeholders raise GitHub issues, an AI swarm plans and builds, PRs are created for review and testing.

## Quick Start — New Project

### 1. Create repo from this template

```bash
gh repo create my-project --template yourorg/swarm-template --private
git clone git@github.com:yourorg/my-project.git
```

### 2. Create infrastructure (manual, ~10 min)

- **Supabase**: Create project at [supabase.com](https://supabase.com), note the URL, anon key, and service role key
- **Vercel**: Import the GitHub repo at [vercel.com](https://vercel.com), link to the repo

### 3. Set GitHub secrets

Go to repo → Settings → Secrets and variables → Actions, and add:

| Secret | Source |
|---|---|
| `SUPABASE_URL` | Supabase project settings → API |
| `SUPABASE_ANON_KEY` | Supabase project settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase project settings → API |
| `VPS_HOST` | Your VPS IP or hostname |
| `VPS_SSH_KEY` | SSH private key for VPS access |
| `CLAUDE_SESSION_KEY` | Claude authentication for the swarm |

### 4. Register on VPS

```bash
ssh your-vps
cd /opt/swarm-platform
./register-project.sh my-project git@github.com:yourorg/my-project.git
```

### 5. Invite stakeholders

Share the repo with stakeholders. Point them to [docs/stakeholder-guide.md](docs/stakeholder-guide.md).

They create issues using the templates → the swarm handles the rest.

---

## Integrate into an Existing Project

If you already have a project with a GitHub repo, Supabase, and Vercel set up:

### 1. Clone the swarm template

```bash
git clone git@github.com:yourorg/swarm-template.git /tmp/swarm-template
```

### 2. Run the integration script

```bash
cd /tmp/swarm-template
./scripts/integrate.sh /path/to/your-existing-project
```

This copies the swarm files (`.swarm/`, `scripts/`, `.github/`, `swarm-state.json`, docs) into your project without touching your existing code.

### 3. Fill in `docs/project-context.md`

**This is the most important step.** Open `docs/project-context.md` and describe your existing codebase — the stack, folder structure, naming conventions, data model, and any patterns agents should follow. All agents read this file before doing any work.

### 4. Update `.swarm/config.yaml`

Set `project_name`, `repo`, and adjust the `stack` section to match your project.

### 5. Set GitHub secrets and register on VPS

Same as steps 3–4 in the new project setup above.

### 6. Commit and push

```bash
cd /path/to/your-existing-project
git add -A
git commit -m "chore: integrate swarm agent pipeline"
git push
```

Stakeholders can now create issues and the swarm will work within your existing codebase.

---

## How It Works

```
Stakeholder creates Issue (using template)
        ↓
Issue labeled "ready-to-build"
        ↓
GitHub Action notifies VPS → Swarm starts
        ↓
Discovery agents ask questions (issue comments)
        ↓
Stakeholder answers on the issue thread
        ↓
Planning agents create plan → PR opened (draft)
        ↓
Stakeholder reviews plan on PR, approves
        ↓
Development agents build (TDD, visual QA)
        ↓
PR updated with implementation + preview URL
        ↓
Stakeholder tests on Vercel preview
        ↓
Tech review required to merge → production
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full swarm architecture, agent roles, and state machine design.
