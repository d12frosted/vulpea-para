# 4. Resource is the baseline reference note

Status: accepted

## Context

PARA's third bucket, Resources, is the vaguest: "reference I might want later." In a real vault almost every note is reference of some kind, and the facets model (ADR 0001) says a note can be a Resource and also something else (a person is a Resource and an Area).

## Decision

A Resource is the baseline facet: a file-level note that has not been archived. We do not require a special "resource" tag. Areas are Resources too, because you still look things up in them. Projects are headings and are never resources.

## Consequences

- No bookkeeping. Any reference note is a Resource just by being a note.
- `vulpea-para-resource-p` is broad on purpose. A "pure resources" view is built by subtracting the other facets (the areas), not by a narrower predicate.
- It depends on what "archived" means, so it leans on ADR 0005.
