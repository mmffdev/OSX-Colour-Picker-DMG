---
name: userjourney
description: Create or update Colorgain user journeys in UserJourney.md from implemented app behaviour, separating user actions, system responses, recovery and saved outcomes for future help content.
---

# Shared user-journey skill and memory

This is the single shared instruction source for Codex and Claude. When Rick writes `<userjourney>`, or asks to add/update an app journey, read this file and [UserJourney.md](../UserJourney.md). If no area is named, document the work just completed in the conversation.

## Durable project decisions

- `UserJourney.md` at the repository root is the growing journey collection and source for future help. Keep existing journeys and their stable `UJ-001` identifiers; update the relevant entry rather than duplicating it.
- Write from the user's perspective in plain British English, using **Colorgain** and exact visible control labels. Explain the task and outcome, not the development chronology.
- Make **what the user does** and **what the system does/shows** explicit. Include choices, blocked states, recovery and the final artefact or result.
- Distinguish what is saved automatically, saved explicitly, copied to the clipboard, retained only in the current session, or unchanged. A copied record is not a persisted approval.
- Describe implemented behaviour as implemented. Keep proposals and uncertain behaviour visibly separate; do not turn recommendations, passing tests or a simulated fixture into product or certification claims.

## Workflow

1. Read the collection index and relevant journey. Read the [component registry](c_layout_registry.md) before locating app sections, then inspect the relevant current source and existing help. Use native observations already available; verify disputed behaviour when needed. If verification is unavailable, state that in editorial notes rather than inventing it.
2. Add a goal, entry route, prerequisites, a user/system step table, meaningful exceptions/recovery, and what the user leaves with. Scale detail to the task; use one journey per distinct user goal.
3. Reuse a stable ID for the same goal; assign the next unused ID for a new goal. Update the collection's linked index. Mark implementation/verification status and review date.
4. Put code links, evidence and publication questions in a short **Editorial evidence** subsection, separate from the help prose. Do not expose temporary developer paths or test-only launch commands as normal user instructions.
5. Check control names, decisions, persistence claims, relative links and consistency with other journeys. Preserve unrelated edits. Report the document and journeys changed.

A journey request authorizes documentation work, not application changes, new backlog entries or publishing the help system. Prepare the Markdown so it can later be adapted into help; do not wire it into the app without that request.

## Memory maintenance

When Rick agrees a reusable journey-writing rule, update it here and keep both agent entry points linked to this file. Keep feature-specific facts in the relevant journey, not in this skill. Keep this file lean; add a lazily linked `c_c_*.md` reference only when a substantial specialist workflow warrants it. Do not create a second Claude or Codex copy of these instructions.
