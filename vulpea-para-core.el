;;; vulpea-para-core.el --- Core PARA model: tags and bucket predicates -*- lexical-binding: t; -*-
;;
;; Copyright (c) 2024-2026 Boris Buliga <boris@d12frosted.io>
;;
;; Author: Boris Buliga <boris@d12frosted.io>
;; Maintainer: Boris Buliga <boris@d12frosted.io>
;;
;; URL: https://github.com/d12frosted/vulpea-para
;;
;; License: GPLv3
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; The core PARA model: the tags that carry a note's role, and the
;; predicates that read a note's buckets back out.
;;
;; Buckets are facets, not walls, so the predicates are independent and
;; are allowed to overlap (a person note is both an area and a resource).
;;
;;; Code:

(require 'vulpea-note)

(defgroup vulpea-para nil
  "PARA method on top of Vulpea."
  :group 'vulpea
  :prefix "vulpea-para-")

;;; Tags
;;
;; A note's PARA role is carried by tags, never by where the file
;; lives.  These are the tag names vulpea-para looks for.  Change them
;; if your vault speaks a different language.

(defcustom vulpea-para-area-tag "area"
  "Tag that marks a file-level note as a PARA area."
  :type 'string
  :group 'vulpea-para)

(defcustom vulpea-para-project-tag "project"
  "Tag that marks a heading as a PARA project."
  :type 'string
  :group 'vulpea-para)

(defcustom vulpea-para-agenda-tag "agenda"
  "Tag added to files that currently hold open work.

You do not set this one by hand.  It is maintained for you, and the
agenda is then simply the set of notes that carry it."
  :type 'string
  :group 'vulpea-para)

(defcustom vulpea-para-people-tag "people"
  "Tag marking person notes.

Used by `vulpea-para-agenda-person' and the meeting capture, which file
meetings under the person they are about."
  :type 'string
  :group 'vulpea-para)

;;; Bucket predicates
;;
;; PARA buckets are facets, not walls: a note can be more than one at
;; once (a person you keep notes on is a resource, and also an area if
;; you keep up the relationship).  So each predicate answers one
;; question on its own, and they are free to overlap.  See
;; docs/adr/0001-buckets-are-facets-not-walls.md.

(defun vulpea-para-area-p (note)
  "Return non-nil when NOTE is a PARA area.

An area is a file-level note, one whole file, tagged with
`vulpea-para-area-tag'."
  (and (= (vulpea-note-level note) 0)
       (vulpea-note-tagged-any-p note vulpea-para-area-tag)))

(defun vulpea-para-project-p (note)
  "Return non-nil when NOTE is a PARA project.

A project is a heading, not a whole file, tagged with
`vulpea-para-project-tag'.  Projects live inside the area they
belong to, so they are always heading-level notes."
  (and (> (vulpea-note-level note) 0)
       (vulpea-note-tagged-any-p note vulpea-para-project-tag)))

(defun vulpea-para-archived-p (note)
  "Return non-nil when NOTE has been archived.

A note is archived when it carries org's archive tag (directly,
inherited from a parent, or as a file tag) or an ARCHIVE_TIME
property.  This mirrors vulpea's own notion of archived.

Note that vulpea leaves archived notes out of its database by default
\(see `vulpea-db-exclude-archived'), so in the usual setup archived
notes do not appear in queries at all; this predicate matters when you
hold a note in hand, or when you index archives on purpose."
  (let ((archive-tag (or (bound-and-true-p org-archive-tag) "ARCHIVE")))
    (or (and (assoc "ARCHIVE_TIME" (vulpea-note-properties note)) t)
        (and (member archive-tag (vulpea-note-tags note)) t))))

(defun vulpea-para-resource-p (note)
  "Return non-nil when NOTE is a PARA resource.

A resource is the baseline: a file-level reference note that has not
been archived.  Areas are resources too (you still look things up in
them), which is the facets-not-walls model in action.  Callers that
want \"resources that are not areas\" subtract `vulpea-para-area-p'
themselves."
  (and (= (vulpea-note-level note) 0)
       (not (vulpea-para-archived-p note))))

(defun vulpea-para-note-buckets (note)
  "Return the list of PARA buckets NOTE belongs to.

The result is a subset of (area project resource archive), in that
order.  Buckets are facets, not walls, so a note can be in more than
one at once: a person note is both `area' and `resource'."
  (let (buckets)
    (when (vulpea-para-area-p note) (push 'area buckets))
    (when (vulpea-para-project-p note) (push 'project buckets))
    (when (vulpea-para-resource-p note) (push 'resource buckets))
    (when (vulpea-para-archived-p note) (push 'archive buckets))
    (nreverse buckets)))

(provide 'vulpea-para-core)
;;; vulpea-para-core.el ends here
