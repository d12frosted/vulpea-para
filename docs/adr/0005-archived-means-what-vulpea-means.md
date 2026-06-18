# 5. Archived means what vulpea already means by it

Status: accepted

## Context

"Archive" can be signalled several ways: an `* Archive :ARCHIVE:` subtree, an `.archive/` directory, org's `ARCHIVE_TIME` and friends, or a DONE state. We need one answer. There is also a twist worth knowing: vulpea already has a notion of archived (`vulpea-db--archived-p`) and, by default (`vulpea-db-exclude-archived` is `t`), it leaves archived notes out of the database entirely.

## Decision

We adopt vulpea's own definition. A note is archived when it carries org's archive tag (directly, inherited from a parent, or as a file tag) or an `ARCHIVE_TIME` property. `vulpea-para-archived-p` mirrors that. A DONE state is "done", not "archived"; the two are different.

Because vulpea excludes archived notes by default, the active PARA views get "archive is out of sight" for free: archived notes are simply not in the database, so areas, projects, resources, and the agenda never show them. Seeing the archive on purpose (a dormant but searchable view) means opting in, by setting `vulpea-db-exclude-archived` to nil.

Archiving as an action moves a finished project under its area's `* Archive :ARCHIVE:` subtree, after which it drops out of the active database on the next sync.

## Consequences

- One predicate, consistent with vulpea, with no guessing between mechanisms.
- Active queries do not even need to filter archived notes; the database already did it.
- An archive view is a separate, opt-in concern, noted for later.
- Work that is DONE but not yet archived still shows up, which is correct: it is finished but still living in its area until you archive it.
