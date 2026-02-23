# Architecture

## Swarm System Architecture

### Overview

This project is developed by an autonomous multi-agent system (the "swarm"). The swarm reads GitHub issues, plans implementations, builds features using TDD, and creates PRs for review.

### Pipeline Stages

```
Issue Created → Discovery → Planning → Development → Visual QA → Review → Tech Merge
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

- **Agents ↔ Stakeholders**: GitHub issue comments and PR comments
- **Agents ↔ Agents**: `swarm-state.json` and doc files in `docs/`
- **Agents ↔ Code**: Git commits on feature branches

### Technology Stack

| Layer | Technology |
|---|---|
| Database & Auth | Supabase (PostgreSQL + Auth + RLS) |
| Hosting | Vercel (preview deploys per PR) |
| Testing | Vitest |
| Visual QA | Playwright |
| Agent Runtime | Claude Code CLI |
| Orchestration | Bash + Git |
| CI/CD | GitHub Actions |

### Event-Driven Workflow Model

The swarm runs entirely on GitHub Actions, triggered by GitHub events — no long-running server required.

| Workflow | Trigger | Purpose |
|---|---|---|
| `swarm-discovery` | Issue labeled `ready-to-build`, `workflow_dispatch` | Runs discovery + planning agents, opens draft PR |
| `swarm-build` | PR approved or `/approve-plan` comment | Runs development, visual QA, and review agents |
| `swarm-feedback` | Comment on `swarm-working` issue | Clears human-input flag, re-triggers discovery |

The orchestrator (`scripts/orchestrator.sh`) is a single-invocation state machine executor. It reads the current stage from `swarm-state.json`, runs the appropriate agents, and exits. If human input is needed, it commits state and exits with code 42 — the feedback workflow resumes it when the human responds.

Concurrency is managed per-issue using GitHub Actions concurrency groups, ensuring only one workflow runs per issue at a time.

---

## Project Architecture

*This section is populated by the Architect agent during the Discovery stage for each feature.*
