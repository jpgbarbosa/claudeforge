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
| Review | Reviewer | Checks code quality, security, documentation |

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

---

## Project Architecture

*This section is populated by the Architect agent during the Discovery stage for each feature.*
