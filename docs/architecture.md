# Architecture

## Swarm System Architecture

### Overview

This project is developed by an autonomous multi-agent system (the "swarm"). The swarm reads GitHub issues, plans implementations, builds features using TDD, and creates PRs for review.

### Pipeline Stages

```
Issue Created -> Discovery -> Planning -> Development -> Visual QA -> Review -> Tech Merge
```

### Agent Roles

| Stage | Agent | Responsibility |
|---|---|---|
| Discovery | Business Analyst | Clarifies business goals, asks stakeholder questions |
| Discovery | Product Strategist | Creates user stories and acceptance criteria |
| Discovery | Architect | Designs data model, API surface, component structure |
| Planning | Tech Lead | Breaks spec into ordered, testable tasks |
| Development | Developer | Implements tasks using TDD |
| Visual QA | QA Agent | Tests the running app in a browser |
| Review | Reviewer | Checks code quality, security, documentation, updates project context |

### State Management

All swarm state lives in `swarm-state.json` at the repo root. This file tracks:
- Current stage and status
- Active issue number
- Task list with completion status
- Whether human input is needed

### Communication

- **Agents <-> Stakeholders**: GitHub issue comments and PR comments
- **Agents <-> Agents**: `swarm-state.json` and doc files in `docs/`
- **Agents <-> Code**: Git commits on feature branches

### Technology Stack

| Layer | Technology |
|---|---|
| Database & Auth | Supabase (PostgreSQL + Auth + RLS) |
| Hosting | Vercel (preview deploys per PR) |
| Testing | Vitest |
| Visual QA | Playwright |
| Agent Runtime | Claude Code Action (`anthropics/claude-code-action@v1`) |
| CI/CD | GitHub Actions |

### Event-Driven Workflow Model

The swarm runs entirely on GitHub Actions, triggered by GitHub events — no long-running server required. Each agent runs as a separate `claude-code-action` step within its workflow.

| Workflow | Trigger | Purpose |
|---|---|---|
| `swarm-discovery` | Issue labeled `ready-to-build`, `workflow_dispatch` | Runs discovery + planning agents (4 action steps), opens draft PR |
| `swarm-build` | PR approved or `/approve-plan` comment | Runs development, visual QA (up to 3 cycles), and review agents |
| `swarm-feedback` | Comment on `swarm-working` issue | Clears human-input flag, re-triggers discovery |
| `claude` | `@claude` mention on issue/PR | Interactive discussion — read-only, no commits |

Discovery agents (BA, PS, Architect, Tech Lead) each run as a separate `claude-code-action` step in `swarm-discovery.yaml`. Between each agent, a bash step checks `human_input_needed` from `swarm-state.json`. If true, the workflow ends and the feedback workflow resumes it when the human responds.

Build agents (Developer, Visual QA, Reviewer) run as `claude-code-action` steps in `swarm-build.yaml`. Visual QA can trigger up to 3 dev rework cycles. After QA passes, the Reviewer runs and the PR is marked ready for human tech review.

Concurrency is managed per-issue using GitHub Actions concurrency groups, ensuring only one workflow runs per issue at a time.

---

## Project Architecture

*This section is populated by the Architect agent during the Discovery stage for each feature.*
