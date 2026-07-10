;;; vulpea-para-refile.el --- Refile across the whole vault -*- lexical-binding: t; -*-
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
;; Refile targets for the whole vault, not just the agenda.
;;
;; With the self-updating agenda, `org-agenda-files' is only the files
;; that hold open work, so building refile targets from it would let you
;; refile only into notes that already have work.  That is backwards:
;; refiling is exactly how a task reaches a note that had none.
;;
;; The hook org provides is that the FILES part of an
;; `org-refile-targets' entry may be a function.  `vulpea-para-refile-files'
;; is that function: it asks the database for every live file-level note
;; (areas first, then the rest), so refile from the agenda, or anywhere
;; else, can reach the whole vault.  Pair it with
;; `vulpea-para-refile-verify-target' to keep archived subtrees out:
;;
;;   (setq org-refile-targets \\='((vulpea-para-refile-files :maxlevel . 3))
;;         org-refile-use-outline-path \\='file
;;         org-outline-path-complete-in-steps nil
;;         org-refile-target-verify-function
;;         #\\='vulpea-para-refile-verify-target)
;;
;; `vulpea-para-setup-defaults' wires all of this for you.
;;
;;; Code:

(require 'org)
(require 'seq)
(require 'vulpea-note)
(require 'vulpea-para-core)
(require 'vulpea-para-db)

(defcustom vulpea-para-refile-files-filter nil
  "Predicate keeping refile candidate notes, or nil to keep all.

Called with a file-level `vulpea-note'; return non-nil to keep it.  Use
it to hold some notes (for example a cemetery, or generated files) out
of the refile targets."
  :type '(choice (const :tag "Keep all" nil)
                 (function :tag "Predicate"))
  :group 'vulpea-para)

(defun vulpea-para-refile-files ()
  "Return the file paths of all refile candidate notes.

These are all live (not archived) file-level notes in the vault, with
area files first so the PARA pillars surface at the top of the target
list.  When `vulpea-para-refile-files-filter' is set, notes it rejects
are left out.

Use it as the FILES part of an `org-refile-targets' entry:

  (setq org-refile-targets
        \\='((vulpea-para-refile-files :maxlevel . 3)))"
  (let ((notes (vulpea-para-resources)))
    (when vulpea-para-refile-files-filter
      (setq notes (seq-filter vulpea-para-refile-files-filter notes)))
    (seq-uniq
     (append
      (mapcar #'vulpea-note-path (seq-filter #'vulpea-para-area-p notes))
      (mapcar #'vulpea-note-path notes)))))

(defun vulpea-para-refile-verify-target ()
  "Return non-nil when the heading at point is a valid refile target.

Archived headings are not, and the check moves point past the archived
subtree so its children are never offered either.  Meant for
`org-refile-target-verify-function'."
  (if (member org-archive-tag (org-get-tags))
      (progn (org-end-of-subtree t t) nil)
    t))

(provide 'vulpea-para-refile)
;;; vulpea-para-refile.el ends here
