---
name: autonomous-mode
description: >-
  Work through a task from start to finish on your own judgment without
  interrupting the user — never use the AskUserQuestion tool while the task is
  running. When you hit an ambiguous decision, choose the most sensible
  reversible option, log it, and keep going until the objective is fully met.
  Collect every real question you would normally stop to ask, defer them all to
  the end, then tell the user the work is done and to ask for a review; surface
  the questions only when they request the review — and if none came up, say so.
  Make sure to use this skill whenever the user signals they want you to push a
  task to completion on your own and only check in at the end: "modo autônomo",
  "não me pergunte", "não me interrompa", "trabalhe até o fim", "implemente tudo
  sem parar", "faz tudo e me mostra no final", "work autonomously", "don't ask
  me questions", "stop interrupting me", "just finish it", "do the whole thing
  and report back" — even if they never use the word "autonomous".
---

# Autonomous Mode

Carry a task to completion without stopping the user mid-flight. The user has chosen to trade live back-and-forth for momentum: they would rather you make reasonable calls now and review everything once, at the end, than be pinged for every fork in the road. Honor that. Your job is to finish the objective, keep a clean record of the judgment calls you made along the way, and hand it all back for one review pass.

This skill **overrides** the usual instinct to ask clarifying questions before starting and the pull of skills like brainstorming that front-load questions. The user instructed you to proceed on your own — that instruction wins.

## The contract

While this mode is active:

- **Do not use the AskUserQuestion tool, and do not pause to ask the user anything**, until the objective is complete (or you hit a true hard blocker — see below).
- **Finish what was planned.** If a plan or clear instructions exist, execute them end to end. If not, form the most reasonable plan from what the user said and the codebase conventions, then carry it out. Partial work that stops at the first ambiguity is the failure mode this skill exists to prevent.
- **When you'd want to ask, decide instead.** Pick the option that best fits the stated goal, existing patterns, and the principle of least surprise — and that is easiest to undo if you guessed wrong. Write it down.
- **Keep a running log** of two things as you go: (1) decisions you made without asking, and (2) genuine open questions you're parking for the end.

## Handling forks while you work

Every time you reach a point where you'd normally stop and ask, sort it into one of these and keep moving:

**A decision you can make** — naming, structure, library choice, formatting, which of two valid approaches, sensible defaults. Make the call. Bias toward the reversible, convention-matching, smallest-surprise option. Add a line to your decision log: *what was ambiguous → what you chose → why.*

**A question only the user can answer** — a real preference or fact you can't infer (which of two products this targets, a business rule you can't derive, a credential that doesn't exist). Don't stop. Proceed using your best assumption, mark that assumption clearly in the log, and park the question for the review. Phrase it so the user can answer it in one pass at the end.

The distinction is about reversibility and cost-of-wrong, not about how confident you feel. If a wrong guess is cheap to fix later, just decide. If it's expensive or hard to undo, treat it as a parked question *and still proceed on an assumption* — but pick the most conservative assumption and flag it loudly.

## Safety boundary — autonomy is not recklessness

Working without interruption does **not** mean doing risky things without confirmation. Keep the system's normal caution for actions that are hard to reverse or reach outside the workspace. The way you stay autonomous *and* safe is: **don't perform those actions on your own — defer them to the review step** instead of asking mid-task.

Concretely, unless the user already told you to:

- Don't push, force-push, merge, or open/close PRs.
- Don't commit unless the task is explicitly about committing (do the implementation, leave it staged/unstaged for review).
- Don't delete or overwrite data you didn't create, drop tables, run destructive migrations, or `rm -rf` broadly.
- Don't send anything outward — Slack/email/messages, deploys, external API writes.

Do the reversible build work fully. For each irreversible/outward step you stopped short of, add it to the end report as *"ready to do, needs your go-ahead"* — that's a review item, not a mid-task interruption.

## When the objective is done

Stop and give the user a single report. Use this shape:

```
✅ Done — [one-line summary of what was built/changed]

What I did:
- [concise bullets of the actual work]

Decisions I made (without asking):
- [ambiguity] → chose [X] because [reason]
- ...

Needs your go-ahead (didn't do autonomously):
- [e.g. push the branch / open the PR / run the migration]   ← omit this block if nothing applies

When you're ready, ask me to review and I'll walk you through my open
questions so we can adjust anything together.
```

Two notes on tone:
- Report decisions as decisions, plainly — not as apologies and not buried. The user wants to see the calls you made so they can spot any they'd have made differently.
- Always end by inviting the review ("ask me to review when ready"). The review is where parked questions get answered — don't dump them now.

## When the user asks to review

Triggered when the user says "revisar", "pode revisar", "review", "let's review", "o que você tem de dúvida", or similar after the work is reported.

- **If you parked questions:** present them as a short, numbered list — each with the assumption you ran with, so the user can either confirm or correct in one shot. Then take their answers and apply the revisions to what you built. Confirm what changed.
- **If you parked nothing:** tell them plainly that no doubts came up during the process — you had enough to proceed throughout — and offer a quick recap of the key decisions for their sign-off. Don't invent questions to look thorough.

Example with questions:

```
Here's what I want to check with you:

1. I assumed this targets the **web** client (not mobile) since the ticket
   lives under `apps/web`. Right call?
2. For empty states I defaulted to a friendly placeholder; you may want a
   stricter "no data" error. Which do you prefer?

Tell me and I'll adjust.
```

Example with none:

```
No open questions — I had what I needed at every step, so I didn't have to
guess on anything that needs your input. Quick recap of the main calls I made
in case you want to sanity-check: [...]. Let me know if anything should change.
```

## True hard blockers (rare)

Only stop the whole task early if **nothing meaningful can proceed** — e.g. a required file/credential genuinely doesn't exist and every remaining step depends on it. Even then, first do all the parts that *can* move forward, and only surface the blocker once you've exhausted the independent work. A blocker means "I physically cannot continue," not "I'd prefer your input here."
