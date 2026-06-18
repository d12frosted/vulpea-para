# 1. Buckets are facets, not walls

Status: accepted

## Context

PARA has four buckets: Projects, Areas, Resources, Archives. The tempting model is that every note lives in exactly one of them, the way a file lives in exactly one folder.

Real notes do not behave like that. A person you keep notes on is a Resource (reference you look things up in) and, if you keep up the relationship, also an Area (meetings and tasks gather under them). Forcing one bucket means picking a drawer and feeling wrong about it. The whole reason this setup is pleasant is that buckets are facets of a note, not walls between notes.

## Decision

A note can satisfy more than one bucket at once. Each bucket is its own yes/no predicate (`vulpea-para-area-p`, `vulpea-para-project-p`, and so on), and they are allowed to overlap. We do not compute a single "primary bucket". Where a caller wants the whole picture, a helper returns the set of buckets a note belongs to.

## Consequences

- Predicates stay simple and independent; there are no precedence rules to argue about.
- Queries can return overlapping sets (the areas and the resources may share notes). That is correct, not a bug, and callers should expect it.
- "What bucket is this note in" is the wrong question. "Which buckets" is the right one.
