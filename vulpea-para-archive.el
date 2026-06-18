;;; vulpea-para-archive.el --- Archive finished projects -*- lexical-binding: t; -*-
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
;; Letting go.  Archiving a finished project moves it under its area's
;; own Archive subtree, where it leaves the active views (vulpea drops
;; archived notes from the database) while staying in the file, still
;; searchable.  See docs/adr/0005-archived-means-what-vulpea-means.md.
;;
;;; Code:

(require 'org)
(require 'org-archive)
(require 'vulpea-note)
(require 'vulpea-select)
(require 'vulpea-para-core)
(require 'vulpea-para-db)

(defcustom vulpea-para-archive-location "::* Archive"
  "Where `vulpea-para-archive-project' files a finished project.

This is an `org-archive-location'.  The default keeps the project in
the same file, under a top-level `Archive' heading."
  :type 'string
  :group 'vulpea-para)

(defun vulpea-para--archive-tag ()
  "Return org's archive tag, defaulting to \"ARCHIVE\"."
  (or (bound-and-true-p org-archive-tag) "ARCHIVE"))

(defun vulpea-para--ensure-archive-heading ()
  "Make sure the buffer has a top-level Archive heading tagged ARCHIVE.

The tag is what makes the whole archive subtree (a project and its
tasks) drop out of vulpea's active database, so we set it rather than
leave the heading bare."
  (org-with-wide-buffer
   (goto-char (point-min))
   (if (re-search-forward "^\\* Archive\\b" nil t)
       (org-back-to-heading t)
     (goto-char (point-max))
     (unless (bolp) (insert "\n"))
     (insert "* Archive\n")
     (org-back-to-heading t))
   (let ((tag (vulpea-para--archive-tag))
         (tags (org-get-tags nil t)))
     (unless (member tag tags)
       (org-set-tags (cons tag tags))))))

(defun vulpea-para--goto-note (note)
  "Move point to NOTE's heading in the current buffer.

Finds it by id when NOTE has one (robust against earlier edits shifting
positions), and falls back to the note's recorded position."
  (let ((id (vulpea-note-id note)))
    (goto-char (point-min))
    (if (and id (re-search-forward
                 (concat "^[ \t]*:ID:[ \t]+" (regexp-quote id) "[ \t]*$")
                 nil t))
        (org-back-to-heading t)
      (goto-char (vulpea-note-pos note)))))

;;;###autoload
(defun vulpea-para-archive-project (project)
  "Archive PROJECT into its area's Archive subtree.

PROJECT is a project note.  Ensures the file has an Archive heading
tagged with org's archive tag, moves the project's subtree under it via
org's own archiving (see `vulpea-para-archive-location'), and saves the
file.  Once archived, vulpea drops the whole subtree from the active
database, so it leaves every active view while staying in the file.

Interactively, prompts for the project with completion."
  (interactive
   (list (vulpea-select-from "Project" (vulpea-para-projects)
                             :require-match t)))
  (let ((file (vulpea-note-path project))
        (org-archive-location vulpea-para-archive-location))
    (with-current-buffer (find-file-noselect file)
      (vulpea-para--ensure-archive-heading)
      (org-with-wide-buffer
       (vulpea-para--goto-note project)
       (org-archive-subtree))
      (save-buffer))))

(provide 'vulpea-para-archive)
;;; vulpea-para-archive.el ends here
