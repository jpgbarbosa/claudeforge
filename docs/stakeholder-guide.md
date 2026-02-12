# Stakeholder Guide

## How to request features and report bugs

This project uses an AI development team that automatically builds features and fixes bugs based on your requests. Here's how to work with it.

### Creating a request

1. Go to the **Issues** tab in this GitHub repository
2. Click **New issue**
3. Choose a template:
   - **Feature Request** — for new functionality
   - **Bug Report** — for something that's broken
4. Fill in the form as completely as you can. The more detail you provide, the better the result.
5. When you're ready for the AI team to start working, add the **`ready-to-build`** label

### What happens next

Once you label your issue, the AI development team kicks off automatically. Here's what to expect:

**Phase 1: Questions (1–2 hours)**
The AI team may post clarifying questions as comments on your issue. Check back and answer them — the team will wait for your responses before moving forward.

**Phase 2: Plan review (PR created)**
You'll receive a notification that a Pull Request has been created. Open it and review the plan:
- Does the plan match what you intended?
- Is anything missing or misunderstood?

Leave comments on the PR if you want changes. When the plan looks good, comment `/approve-plan` to give the go-ahead.

**Phase 3: Building**
The AI team builds the feature. You don't need to do anything during this phase.

**Phase 4: Testing**
The PR will update with a **preview link** (a Vercel URL). Click it to test the feature in a real environment:
- Does it work as expected?
- Does it look right?
- Any edge cases that break?

Leave your feedback as comments on the PR.

**Phase 5: Tech review**
A technical team member reviews the code and merges the PR when everything is solid. Once merged, the feature goes live.

### Clarifying questions and bypassing them

The AI team may ask clarifying questions on your issue before starting work — for example, to confirm the target user, success criteria, or scope. This helps ensure the final result matches your intent.

If you'd rather the team proceeds immediately with whatever information is available, comment on the issue with:

> **enforce current description**

The team will do its best with the current info, but the result may require more iteration. Other phrases that work: "proceed as-is" or "skip validation".

### Tips for good requests

- **Be specific**: "Users should be able to filter the table by date range" is better than "Improve the table"
- **Include examples**: Screenshots, mockups, or links to similar features help a lot
- **Define success**: How will you know the feature is working correctly?
- **One thing at a time**: Keep each issue focused on a single feature or bug

### Providing feedback

You can provide feedback at two points:
1. **On the issue** — during the questions phase, before any code is written
2. **On the PR** — after reviewing the plan or testing the preview

Both are equally valid. Earlier feedback saves more time.

### Labels you'll see

| Label | Meaning |
|---|---|
| `ready-to-build` | You've approved this issue for the AI team to work on |
| `swarm-working` | The AI team is actively working on this |
| `swarm-review` | Implementation is done, ready for testing and review |
| `swarm-complete` | Merged and deployed |
