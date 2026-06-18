;;; vulpea-para-db.el --- Database-backed PARA queries -*- lexical-binding: t; -*-
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
;; The read API: ask vulpea's database which notes are areas, projects,
;; and resources, and how they relate.  Everything here is a query, and
;; nothing touches a file, so it stays fast even with thousands of notes.
;;
;;; Code:

(require 'seq)
(require 'vulpea-note)
(require 'vulpea-db-query)
(require 'vulpea-para-core)

(defun vulpea-para-areas ()
  "Return all area notes."
  (seq-filter #'vulpea-para-area-p
              (vulpea-db-query-by-tags-some (list vulpea-para-area-tag))))

(defun vulpea-para-projects ()
  "Return all project notes (the project headings across all areas)."
  (seq-filter #'vulpea-para-project-p
              (vulpea-db-query-by-tags-some (list vulpea-para-project-tag))))

(defun vulpea-para-resources ()
  "Return all resource notes, the file-level reference notes.

Areas are resources too; see `vulpea-para-resource-p'.  For a view of
resources that are not areas, remove the areas yourself."
  (seq-filter #'vulpea-para-resource-p
              (vulpea-db-query-by-level 0)))

(defun vulpea-para-area-of (note)
  "Return the area NOTE belongs to, or nil.

A note belongs to the area whose file it lives in.  This returns the
file-level note of NOTE's file when that note is an area, and nil
otherwise (for example a project in a file that is not an area)."
  (when-let* ((path (vulpea-note-path note))
              (file-note (car (vulpea-db-query-by-file-paths (list path) 0))))
    (when (vulpea-para-area-p file-note)
      file-note)))

(defun vulpea-para-projects-in-area (area)
  "Return the projects that live in AREA.

These are the project headings in the area's file."
  (seq-filter #'vulpea-para-project-p
              (vulpea-db-query-by-file-paths (list (vulpea-note-path area)))))

(provide 'vulpea-para-db)
;;; vulpea-para-db.el ends here
