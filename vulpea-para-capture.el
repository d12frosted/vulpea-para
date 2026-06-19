;;; vulpea-para-capture.el --- Capture projects into areas -*- lexical-binding: t; -*-
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
;; Capture that files itself.  Adding a project asks which area it
;; belongs to and drops it straight in, under the area's own Tasks, with
;; a readable category, so you never refile anything by hand.
;;
;;; Code:

(require 'org)
(require 'org-id)
(require 'org-capture)
(require 'vulpea)
(require 'vulpea-note)
(require 'vulpea-select)
(require 'vulpea-para-core)
(require 'vulpea-para-db)

(defun vulpea-para-category (area-title project-title)
  "Return the category string for PROJECT-TITLE under AREA-TITLE.

It reads like \"Area > Project\", which is what makes the agenda line
readable instead of a bare task title."
  (format "%s > %s" area-title project-title))

(defun vulpea-para--goto-tasks-end ()
  "Move point to where a new project should go under the `* Tasks' heading.

Creates a `* Tasks' heading at the end of the file when there is none."
  (goto-char (point-min))
  (if (re-search-forward "^\\* Tasks[ \t]*$" nil t)
      (progn
        (org-back-to-heading t)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n")))
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "* Tasks\n")))

;;;###autoload
(defun vulpea-para-capture-project (area title)
  "Add a project titled TITLE to AREA, and return the new project's id.

AREA is an area note.  This inserts a `** TODO TITLE' heading tagged
with `vulpea-para-project-tag' under the area's `* Tasks' subtree
\(creating Tasks when the file has none), gives it a fresh id and a
CATEGORY of \"Area > TITLE\", and saves the file.

Interactively, prompts for the area with completion and reads the
project title in the minibuffer."
  (interactive
   (list (vulpea-select-from "Area" (vulpea-para-areas) :require-match t)
         (read-string "Project title: ")))
  (let* ((file (vulpea-note-path area))
         (id (org-id-new))
         (category (vulpea-para-category (vulpea-note-title area) title))
         (heading (format
                   "** TODO %s :%s:\n:PROPERTIES:\n:ID:       %s\n:CATEGORY: %s\n:END:\n"
                   title vulpea-para-project-tag id category)))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (vulpea-para--goto-tasks-end)
        (insert heading))
      (save-buffer))
    id))

;;; Capturing an area

(defcustom vulpea-para-capture-area-file-name "area/${timestamp}-${slug}.org"
  "File-name template for a new area, passed to `vulpea-create'."
  :type 'string
  :group 'vulpea-para)

(defcustom vulpea-para-capture-area-body "* Notes\n\n* Tasks\n\n* Archive"
  "Body seeded into a new area note by `vulpea-para-capture-area'.

The default gives an area a place for reference (Notes), its projects
and tasks (Tasks, where `vulpea-para-capture-project' files them), and
finished work (Archive)."
  :type 'string
  :group 'vulpea-para)

;;;###autoload
(defun vulpea-para-capture-area (title &optional no-visit)
  "Create an area note titled TITLE and return it.

Tags the note with `vulpea-para-area-tag', seeds it with
`vulpea-para-capture-area-body', and visits it unless NO-VISIT."
  (interactive (list (string-trim (read-string "Area: "))))
  (when (string-empty-p title)
    (user-error "Area name cannot be empty"))
  (let ((note (vulpea-create
               title vulpea-para-capture-area-file-name
               :tags (list vulpea-para-area-tag)
               :body vulpea-para-capture-area-body)))
    (unless no-visit
      (vulpea-visit note))
    note))

;;; Org-capture building blocks
;;
;; vulpea-para does not set `org-capture-templates'.  These are the
;; pieces you reference from your own templates; see the README.

(defun vulpea-para-capture-task-template ()
  "Return an Org capture template string for a task."
  (string-join
   (list "* TODO %?"
         ":PROPERTIES:"
         (format ":ID:       %s" (org-id-new))
         (format ":CREATED:  %s" (format-time-string "[%Y-%m-%d %H:%M]"))
         ":END:")
   "\n"))

(defun vulpea-para-capture-project-target ()
  "Move point to the Tasks subtree of the project's area.

An Org capture target.  The area is read from the capture property
`:project-area', which `vulpea-para-capture-project-template' sets."
  (let* ((area (org-capture-get :project-area))
         (path (vulpea-note-path area)))
    (set-buffer (org-capture-target-buffer path))
    (unless (derived-mode-p 'org-mode)
      (org-mode))
    (org-capture-put-target-region-and-position)
    (widen)
    (goto-char (point-min))
    (if (re-search-forward
         (format org-complex-heading-regexp-format (regexp-quote "Tasks"))
         nil t)
        (beginning-of-line)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "* Tasks\n")
      (beginning-of-line 0))))

(defun vulpea-para-capture-project-template ()
  "Return an Org capture template for a project filed under its area.

Prompts for an existing area and a title, records the area on the
capture as `:project-area' (used by
`vulpea-para-capture-project-target'), and gives the project a category
of \"Area > Project\"."
  (let* ((area (vulpea-select-from "Area" (vulpea-para-areas)
                                   :require-match t))
         (title (string-trim (read-string "Project: "))))
    (when (string-empty-p title)
      (user-error "Project name cannot be empty"))
    (org-capture-put :project-area area)
    (string-join
     (list (format "* TODO %s :%s:" title vulpea-para-project-tag)
           ":PROPERTIES:"
           (format ":ID:       %s" (org-id-new))
           (format ":CREATED:  %s" (format-time-string "[%Y-%m-%d %H:%M]"))
           (format ":CATEGORY: %s"
                   (vulpea-para-category
                    (or (vulpea-note-meta-get area "short name")
                        (vulpea-note-title area))
                    title))
           ":END:"
           ""
           "%?")
     "\n")))

;;; Capturing a meeting under a person

(defcustom vulpea-para-capture-meeting-headline "Meetings"
  "Heading under which meetings are filed in a person's note."
  :type 'string
  :group 'vulpea-para)

(defun vulpea-para-capture-meeting-target ()
  "Move point to the meetings heading of the meeting's person.

An Org capture target.  The person is read from the capture property
`:meeting-person' (set by `vulpea-para-capture-meeting-template'); when
there is none, `org-default-notes-file' is used."
  (let* ((person (org-capture-get :meeting-person))
         (path (if (and person (vulpea-note-id person))
                   (vulpea-note-path person)
                 org-default-notes-file))
         (headline vulpea-para-capture-meeting-headline))
    (set-buffer (org-capture-target-buffer path))
    (unless (derived-mode-p 'org-mode)
      (org-mode))
    (org-capture-put-target-region-and-position)
    (widen)
    (goto-char (point-min))
    (if (re-search-forward
         (format org-complex-heading-regexp-format (regexp-quote headline))
         nil t)
        (beginning-of-line)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "* " headline "\n")
      (beginning-of-line 0))))

(defun vulpea-para-capture-meeting-template ()
  "Return an Org capture template for a meeting with a selected person.

Records the person on the capture as `:meeting-person' (used by
`vulpea-para-capture-meeting-target').  Uses the MEETING keyword and a
REFILE tag, matching a common task-management convention."
  (let ((person (vulpea-select-from
                 "Person"
                 (vulpea-db-query-by-tags-some
                  (list vulpea-para-people-tag)))))
    (org-capture-put :meeting-person person)
    (if (vulpea-note-id person)
        "* MEETING [%<%Y-%m-%d %a>] :REFILE:MEETING:\n%U\n\n%?"
      (concat "* MEETING with "
              (vulpea-note-title person)
              " on [%<%Y-%m-%d %a>] :MEETING:\n%U\n\n%?"))))

(provide 'vulpea-para-capture)
;;; vulpea-para-capture.el ends here
