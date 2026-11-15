# Domain Docs

This repository uses a single-context domain documentation layout.

## Before exploring, read these

- `GLOSSARY.md` at the repository root.
- Relevant ADRs under `docs/adr/`.

If these files do not exist, proceed silently. Do not flag their absence
or suggest creating them upfront. The domain-modeling skill creates them
lazily when terms or decisions are resolved.

## File structure

- `GLOSSARY.md`: shared domain terminology.
- `docs/adr/`: architectural decision records.

## Use the glossary's vocabulary

When naming domain concepts in issues, proposals, hypotheses, or tests,
use the terms defined in `GLOSSARY.md`. Avoid synonyms it explicitly rejects.

If a needed concept is missing, reconsider whether it fits the project's
language or note a genuine gap for domain-modeling.

## Flag ADR conflicts

If a proposal contradicts an existing ADR, surface the conflict explicitly
rather than silently overriding the decision. Identify the ADR and explain
why it may be worth reopening.
