# MOM startup discovery

First-run adaptive discovery for MOM Native.

## Shape

- 200 mapped discovery nodes across 20 domains.
- Four routing gateways always begin the path.
- Every discovery node has three prompt phrasings and four mapped response paths.
- Answers contribute weighted, revisable personality/support signals and open other domains.
- Clear answers can finish setup after roughly 8 questions.
- Mixed/context-dependent answers keep exploration open, generally to about 12 questions.
- Startup never exceeds 20 questions.
- Remaining discoveries stay available for later conversational learning.

## Files

- `discovery_models.dart` — node, choice, answer, progress, and prompt-summary model.
- `discovery_templates.dart` — mapped answer possibilities, signals, and branch openings.
- `discovery_bank.dart` — the 200 discovery nodes.
- `discovery_engine.dart` — gateway order, route scoring, branch selection, and stopping logic.
- `discovery_store.dart` — local persistence.
- `discovery_screen.dart` — horizontal answer carousel UI.
- `PSYCHOLOGY_BASIS.md` — research foundations and non-diagnostic guardrails.

The result is intentionally closer to a branching game conversation than a questionnaire. The visible question number is only progress through the current route, not a fixed question list.
