# Project Context

> **This file is read by all swarm agents before they start working.**
> Fill it in so agents understand your existing codebase and conventions.

## Overview

<!-- What does this project do? One paragraph. -->

## Stack

| Layer | Technology | Notes |
|---|---|---|
| Frontend | | e.g., Next.js 14, React, Tailwind |
| Backend | | e.g., Supabase Edge Functions, Express |
| Database | | e.g., Supabase (PostgreSQL) |
| Auth | | e.g., Supabase Auth, NextAuth |
| Hosting | | e.g., Vercel |
| Testing | | e.g., Vitest, Playwright |

## Folder Structure

<!-- Describe the key directories. Example: -->
<!--
```
src/
├── app/           # Next.js app router pages
├── components/    # Reusable UI components
├── lib/           # Utility functions and Supabase client
├── hooks/         # Custom React hooks
└── types/         # TypeScript type definitions
```
-->

## Key Conventions

<!-- List the patterns agents should follow. Examples: -->
<!--
- Components use PascalCase (e.g., UserCard.tsx)
- API routes go in src/app/api/
- Supabase client is initialized in src/lib/supabase.ts
- All database queries go through server-side functions, never client-side
- We use Tailwind for styling, no CSS modules
- Error handling: all async functions use try/catch with typed errors
-->

## Data Model

<!-- Describe existing tables and key relationships. Example: -->
<!--
- `users` — managed by Supabase Auth
- `profiles` — extends users, has display_name, avatar_url
- `projects` — belongs to a user, has title, description, status
- `tasks` — belongs to a project, has title, assignee, due_date
- RLS: users can only see their own projects and tasks
-->

## Environment Variables

<!-- List the env vars the project uses (not the values). Example: -->
<!--
- NEXT_PUBLIC_SUPABASE_URL
- NEXT_PUBLIC_SUPABASE_ANON_KEY
- SUPABASE_SERVICE_ROLE_KEY
- NEXT_PUBLIC_APP_URL
-->

## Important Patterns

<!-- Anything else agents need to know. Examples: -->
<!--
- We use optimistic updates for UI responsiveness
- All forms use react-hook-form with zod validation
- Toasts for success/error feedback (using sonner)
- Protected routes check auth in middleware.ts
- Database migrations are in supabase/migrations/
-->

## Known Limitations

<!-- Anything agents should be aware of. Examples: -->
<!--
- No real-time features yet (planned)
- Mobile responsive but not optimized
- No i18n support
-->
