# records/reviews/

Archived design reviews and architecture stress-tests. What a review panel found, when, against
which commit — the standing record of "the system was examined and here is what came back."

**Append-only, like all of `records/`.** A review is a snapshot of what was true and what was
believed at a point in time. A later review supersedes an earlier one by citing it; the earlier one
is never edited to match the newer findings. The value is the honest record of what the design
looked like under scrutiny on that date.

The distinction from the siblings:

- [`../plans/`](../plans/) holds the *implementation plan that acts on* a review's findings. A review
  says what is wrong; a plan says what will be done about it. They are separate artifacts and cite
  each other.
- [`../experiments/`](../experiments/) records what was *run* against real infrastructure. A review
  is analysis of the design and code as they stand, not a measurement of a live system — though a
  review's findings frequently ask for experiments (e.g. "run L-06").
- [`../rfcs/`](../rfcs/) holds *proposals* under discussion. A review evaluates what already exists.

## Naming

`YYYY-MM-DD-kebab-title.md`. State the commit sha reviewed, the panel, and the method in the header,
so the findings can be read against the exact tree they were made on.
