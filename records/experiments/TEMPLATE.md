# Experiment: <Title>

**Date:** YYYY-MM-DD
**Status:** running | concluded | abandoned
**Author:** <name or agent>

## Question

What you wanted to find out. One sentence, answerable, decided **before** the run rather than
fitted to the result afterwards.

## Hypothesis

What you expected, and why. Write this down before running — an experiment whose hypothesis was
written after the outcome is a story, not a result.

## Setup

Enough for someone to repeat it:

- Model and version
- Tools and permissions granted
- Prompt or task given (link the file; do not paraphrase)
- Loop configuration: iteration budget, stopping condition, autonomy level
- Repo state: commit sha
- What the agent could reach — network, chain, testnet funds, machines

## Result

What actually happened. Include the transcript or a link to it.

## Cost

Tokens, wall-clock, and anything it spent. Relevant because spec §2.7 treats autonomous spend as
the top residual risk — an experiment that transacts is also a test of the envelope.

## Conclusion

Whether the hypothesis held. **If it did not, say so plainly and keep the record** — negative
results about agentic loops are the most reusable thing in this directory and the least likely to
get written down.

## What surprised us

The part that was not in the hypothesis. Usually the reason the experiment was worth running.

## Follow-ups

What to try next, or what this changes about how the project runs agents. If it changes something
durable, write an ADR.
