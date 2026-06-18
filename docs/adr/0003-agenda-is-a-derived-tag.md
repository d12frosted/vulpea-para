# 3. The agenda is a derived tag

Status: accepted

## Context

Building an agenda by scanning every note does not scale. Past a few thousand files it takes tens of seconds, which makes the agenda useless. But only a small fraction of notes ever hold a task.

## Decision

We treat the agenda as a cached query. On save, vulpea-para checks whether the current file holds any open `TODO` (a not-done heading), and adds or removes an `agenda` tag (`vulpea-para-agenda-tag`) on the file to match. `org-agenda-files` is then built from a database query for that tag, which returns in a few milliseconds.

The `agenda` tag is derived state, a cache. It is only as correct as the save hook, so a file can drift (tagged with no open work, or the reverse). The maintenance doctor reconciles it.

## Consequences

- The agenda is fast and self-updating: a file slips in and out as work appears and finishes.
- The "does this file hold open work" check is generic and not PARA-specific. It may belong in vulpea core rather than here; tracked as an open question in the README.
- Users should not hand-edit the `agenda` tag. It is not theirs to set.
