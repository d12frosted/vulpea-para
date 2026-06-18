# 2. A note's PARA role is carried by tags, not folders

Status: accepted

## Context

Most PARA write-ups map the four buckets onto four folders. That couples two unrelated things: where a file is stored, and how actionable it is. The moment priorities move (which is constantly), you are moving files and repairing links.

vulpea already reads tags, metadata, and links into a fast database. We can let storage be storage and read the role separately.

## Decision

A note's role is determined by tags (and later metadata), never by its path on disk:

- Area: a file-level note tagged `area` (configurable via `vulpea-para-area-tag`).
- Project: a heading tagged `project` (`vulpea-para-project-tag`), with a category of the form `Area > Project name`.
- Resource and Archive: defined in their own ADRs (Resource is the baseline reference note, ADR 0004; Archive is org's archive tag or an `ARCHIVE_TIME` property, ADR 0005).

Tag names are defcustoms, so a vault that uses different words can say so.

## Consequences

- Reclassifying is a tag flip, not a file move. Links never break.
- The same folders (`area/`, `people/`, ...) can hold notes of any role. Folders are about domain and storage, not PARA.
- We depend on tags being indexed correctly, including the local versus inherited distinction, which the queries must be careful about.
