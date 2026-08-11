---
description: Consult federated agent(s) via the agent-comms ask primitive (clone-and-invoke).
---

You are running the **ask** primitive: synchronous cross-agent consultation via `scripts/agent-comms/ask.sh`. Provided by the `agent-comms` feature.

## Preflight: is agent-comms installed?

Before anything else, check that `scripts/agent-comms/ask.sh` exists (e.g. `ls scripts/agent-comms/ask.sh`). If it is missing, the **agent-comms** feature is not installed in this repo. Tell the user:

> `/ask` needs the **agent-comms** feature, which isn't installed here. Enable it with `./scripts/enable-feature.sh agent-comms`, then try again.

Then stop — do not attempt discovery or direct mode.

**Core rule: you are the picker.** Only ever call `ask.sh` in **direct mode** (`ask.sh <agent-id> "<question>"`), which needs no TTY. Never rely on `ask.sh`'s interactive stdin picker and never pipe a selection into it — orchestrate discovery yourself in the conversation.

The user's input is: `$ARGUMENTS`

## Parse the input

Decide direct vs discovery from the first token:

- **Direct mode** if the first token names an agent: an `@<token>`, an `<owner>/<repo>` slug, or a bareword that resolves to a known agent id (exact id, `owner_repo`, or repo basename — the same resolution `ask.sh` uses). Strip a leading `@`. The remainder (with any surrounding quotes stripped) is the question. A quoted remainder is a strong signal the first token is the agent.
- **Discovery mode** otherwise: the whole input is the question and no agent is named.

If a bareword first token is ambiguous (could be an agent id or the start of the question) and the rest is not quoted, prefer discovery and let the user confirm.

## Direct mode

Run the agent, substituting the parsed id and question:

```
bash scripts/agent-comms/ask.sh <agent-id> "<question>"
```

Return the agent's answer, attributed to the agent id.

## Discovery mode

1. Render the candidate list by invoking discovery purely for its table (ignore the harmless `No selection. Nothing asked.` tail — you are not using the picker):

   ```
   bash scripts/agent-comms/ask.sh "<question>"
   ```

   This keeps `ask.sh` the single source of truth for the federation index URL and id-resolution rules — do not fetch the index yourself.
2. Present the numbered candidates to the user and ask which to consult (one, several, or all). Use the candidate descriptions to suggest the most relevant if the choice is obvious, but let the user decide.
3. For **each** chosen agent, call **direct mode** once:

   ```
   bash scripts/agent-comms/ask.sh <agent-id> "<question>"
   ```
4. Return each answer, clearly attributed to its agent.

## Notes

- If `ANTHROPIC_API_KEY` is set, consulted agents print a warning that claude.ai connectors are disabled because the key takes precedence over the claude.ai login. This does not break `ask` — the remote agent answers from its own wiki. Mention it only if the user is troubleshooting connectors.
- This is `ask`-only. The `message` (async DM) and `post` (channel) modes are not part of this command.
