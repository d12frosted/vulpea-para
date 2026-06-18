;;; vulpea-para-doctor.el --- Keep a PARA setup honest -*- lexical-binding: t; -*-
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
;; A small doctor that keeps the setup honest.  It looks for the two
;; inconsistencies that creep in over time: projects that ended up
;; outside any area, and files still carrying the agenda tag after their
;; work is gone.  Each check is a plain query you can call on its own,
;; and `vulpea-para-doctor' shows them together.
;;
;;; Code:

(require 'seq)
(require 'vulpea-note)
(require 'vulpea-db-query)
(require 'vulpea-para-core)
(require 'vulpea-para-db)
(require 'vulpea-para-agenda)

(defcustom vulpea-para-done-keywords '("DONE" "CANCELLED")
  "TODO keywords that count as finished, for database-side checks.

The save-time agenda check uses org's own done and not-done
classification.  This list is the approximation the doctor uses when it
reasons from the database alone, where a file's own keyword setup is
not available."
  :type '(repeat string)
  :group 'vulpea-para)

(defun vulpea-para--note-open-p (note)
  "Return non-nil when NOTE is an open task, in the database sense.

A note is open when it has a TODO keyword that is not one of
`vulpea-para-done-keywords'."
  (let ((todo (vulpea-note-todo note)))
    (and todo (not (member todo vulpea-para-done-keywords)))))

(defun vulpea-para-doctor-orphan-projects ()
  "Return the projects that do not live in any area.

A project should live inside its area's file.  One that does not is
usually a leftover from moving things around by hand."
  (seq-remove #'vulpea-para-area-of (vulpea-para-projects)))

(defun vulpea-para-doctor-stale-agenda-files ()
  "Return the paths of agenda-tagged files that hold no open task.

These files carry the agenda tag but, as far as the database can tell,
have no open work, so the tag is probably stale.  Saving the file fixes
it; this just finds the drift."
  (let ((open-paths (make-hash-table :test 'equal)))
    (dolist (note (vulpea-db-query #'vulpea-para--note-open-p))
      (puthash (vulpea-note-path note) t open-paths))
    (seq-remove (lambda (path) (gethash path open-paths))
                (vulpea-para-agenda-files))))

;;;###autoload
(defun vulpea-para-doctor ()
  "Report PARA inconsistencies in a buffer.

Lists the projects that do not live in any area, and the agenda-tagged
files that appear to hold no open work."
  (interactive)
  (let ((orphans (vulpea-para-doctor-orphan-projects))
        (stale (vulpea-para-doctor-stale-agenda-files)))
    (with-current-buffer (get-buffer-create "*vulpea-para-doctor*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "vulpea-para doctor\n==================\n\n")
        (insert (format "Projects outside any area: %d\n" (length orphans)))
        (dolist (p orphans)
          (insert (format "  - %s (%s)\n"
                          (vulpea-note-title p) (vulpea-note-path p))))
        (insert (format "\nStale agenda tags (no open work): %d\n" (length stale)))
        (dolist (path stale)
          (insert (format "  - %s\n" path)))
        (when (and (null orphans) (null stale))
          (insert "\nAll good. Nothing to fix.\n")))
      (special-mode)
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

(provide 'vulpea-para-doctor)
;;; vulpea-para-doctor.el ends here
