;;; vulpea-para-agenda.el --- Self-updating PARA agenda -*- lexical-binding: t; -*-
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
;; The agenda, kept fast and self-updating.  On save a note file
;; maintains an `agenda' tag that means "I hold open work", and
;; `org-agenda-files' is then just the set of files carrying that tag,
;; fetched from the database in a few milliseconds rather than by
;; walking thousands of files.  See docs/adr/0003-agenda-is-a-derived-tag.md.
;;
;;; Code:

(require 'org)
(require 'org-element)
(require 'org-agenda)
(require 'org-habit)
(require 'seq)
(require 'vulpea-buffer)
(require 'vulpea-db-query)
(require 'vulpea-note)
(require 'vulpea-select)
(require 'vulpea-para-core)
(require 'vulpea-para-db)

(defvar vulpea-db-sync-directories)     ; defined in vulpea-db-sync

(defcustom vulpea-para-open-work-tags '("REFILE")
  "Tags that always count as open work, whatever the TODO state.

A heading carrying one of these (for example REFILE, something waiting
to be sorted) keeps its file on the agenda even with no open TODO."
  :type '(repeat string)
  :group 'vulpea-para)

(defcustom vulpea-para-open-work-files nil
  "Files that always count as holding open work.

A file matched here keeps the `agenda' tag even with no open TODO, so it
never drops off the agenda.  Handy for an inbox you always want in view,
so you remember to empty it.

Each entry is one of:
- a bare file name with no directory, matched against the buffer file's
  base name, so \"inbox.org\" matches wherever the inbox lives;
- an absolute file name, matched against the buffer file;
- a function of one argument, the buffer file's absolute name, returning
  non-nil to match."
  :type '(repeat (choice (file :tag "File name")
                         (function :tag "Predicate")))
  :group 'vulpea-para)

(defun vulpea-para--open-work-path-p (path)
  "Return non-nil when PATH is in `vulpea-para-open-work-files'.

PATH is an absolute file name.  See `vulpea-para-open-work-files'."
  (when path
    (let ((path (expand-file-name path)))
      (seq-some
       (lambda (entry)
         (cond
          ((functionp entry) (funcall entry path))
          ((file-name-absolute-p entry)
           (string-equal (expand-file-name entry) path))
          (t (string-equal entry (file-name-nondirectory path)))))
       vulpea-para-open-work-files))))

(defun vulpea-para--open-work-file-p ()
  "Return non-nil when the current file is in `vulpea-para-open-work-files'."
  (vulpea-para--open-work-path-p (buffer-file-name)))

(defun vulpea-para-buffer-open-work-p ()
  "Return non-nil when there is any open work in the current buffer.

Open work is any of: the file is one of `vulpea-para-open-work-files'; a
not-done TODO heading; a heading tagged with one of
`vulpea-para-open-work-tags'; or a not-done heading carrying an active
timestamp (something with a date still ahead of it).  A buffer with only
DONE or plain headings, or no headings at all, holds none."
  (or
   (vulpea-para--open-work-file-p)
   (org-element-map (org-element-parse-buffer 'headline) 'headline
     (lambda (h)
       (let ((todo-type (org-element-property :todo-type h)))
         (or
          (eq 'todo todo-type)
          (seq-intersection (org-element-property :tags h)
                            vulpea-para-open-work-tags)
          (and
           (not (eq 'done todo-type))
           (org-element-property :contents-begin h)
           (save-excursion
             (goto-char (org-element-property :contents-begin h))
             ;; look for an active timestamp before the next heading, not
             ;; in child subtrees (which :contents-end would include)
             (let ((end (save-excursion
                          (or (re-search-forward
                               org-element-headline-re
                               (org-element-property :contents-end h)
                               t)
                              (org-element-property :contents-end h)))))
               (re-search-forward org-ts-regexp end t)))))))
     nil 'first-match)))

(defun vulpea-para-update-agenda-tag ()
  "Add or drop the agenda tag on the current file to match its open work.

Adds `vulpea-para-agenda-tag' to the file's tags when the buffer holds
any open TODO, and removes it when it does not.  Other tags are left
alone.  This is meant for `before-save-hook' in your note files, and is
a no-op when nothing needs to change."
  (save-excursion
    (goto-char (point-min))
    (let* ((tags (vulpea-buffer-tags-get t))
           (tagged (and (member vulpea-para-agenda-tag tags) t))
           (has-work (and (vulpea-para-buffer-open-work-p) t)))
      (cond
       ((and has-work (not tagged))
        (vulpea-buffer-tags-add vulpea-para-agenda-tag))
       ((and (not has-work) tagged)
        (vulpea-buffer-tags-remove vulpea-para-agenda-tag))))))

(defcustom vulpea-para-agenda-files-filter nil
  "Predicate keeping agenda notes, or nil to keep all.

Called with a `vulpea-note'; return non-nil to keep it.  Use it to hold
some notes (for example a cemetery) out of the agenda file list."
  :type '(choice (const :tag "Keep all" nil)
                 (function :tag "Predicate"))
  :group 'vulpea-para)

(defun vulpea-para-agenda-files ()
  "Return the file paths of notes tagged for the agenda.

These are the files that currently hold open work, which are the only
files `org-agenda' needs to scan.  When `vulpea-para-agenda-files-filter'
is set, notes it rejects are left out."
  (let ((notes (vulpea-db-query-by-tags-some (list vulpea-para-agenda-tag))))
    (when vulpea-para-agenda-files-filter
      (setq notes (seq-filter vulpea-para-agenda-files-filter notes)))
    (seq-uniq (mapcar #'vulpea-note-path notes))))

(defvar vulpea-para-agenda-inhibit-files-update nil
  "When non-nil, `vulpea-para-agenda-files-update' leaves files alone.

Bind it around an `org-agenda' call that sets `org-agenda-files' itself,
so the agenda-mode advice does not overwrite the restriction.
`vulpea-para-agenda-area' binds it to stay scoped to a single file.")

(defun vulpea-para-agenda-files-update (&rest _)
  "Set `org-agenda-files' to the PARA agenda files.

Ignores its arguments, so it works as :before advice on `org-agenda'
and `org-todo-list'.  Does nothing while
`vulpea-para-agenda-inhibit-files-update' is non-nil.  The first update
of a session also checks for files the agenda is missing; see
`vulpea-para-agenda-warn-missing'."
  (unless vulpea-para-agenda-inhibit-files-update
    (setq org-agenda-files (vulpea-para-agenda-files))
    (vulpea-para-agenda--warn-missing)))

;;; Backfill (catching up a vault that predates the mode)
;;
;; The agenda tag is maintained on save, so a file whose open work
;; predates `vulpea-para-agenda-mode' is invisible to the agenda until
;; it happens to be saved again.  These pieces find that drift from the
;; database (no file visits) and fix it in one command.

(defcustom vulpea-para-done-keywords '("DONE" "CANCELLED")
  "TODO keywords that count as finished, for database-side checks.

The save-time agenda check uses org's own done and not-done
classification.  This list is the approximation used when reasoning
from the database alone (the doctor,
`vulpea-para-agenda-missing-files'), where a file's own keyword setup
is not available."
  :type '(repeat string)
  :group 'vulpea-para)

(defun vulpea-para--note-open-p (note)
  "Return non-nil when NOTE is an open task, in the database sense.

A note is open when it has a TODO keyword that is not one of
`vulpea-para-done-keywords'."
  (let ((todo (vulpea-note-todo note)))
    (and todo (not (member todo vulpea-para-done-keywords)))))

(defun vulpea-para-agenda-missing-files ()
  "Return the paths of files holding open work but missing the agenda tag.

These files never show up in the agenda even though, as far as the
database can tell, they hold open work: an open TODO, a heading tagged
with one of `vulpea-para-open-work-tags', or a pin through
`vulpea-para-open-work-files'.  Files whose note is rejected by
`vulpea-para-agenda-files-filter' are kept out on purpose and not
counted.  Run `vulpea-para-agenda-backfill' to tag them all at once.

This is a pure database query; no file is visited."
  (let ((tagged (make-hash-table :test 'equal))
        (paths nil))
    (dolist (note (vulpea-db-query-by-tags-some (list vulpea-para-agenda-tag)))
      (puthash (vulpea-note-path note) t tagged))
    (dolist (note (vulpea-db-query
                   (lambda (note)
                     (or (vulpea-para--note-open-p note)
                         (seq-intersection (vulpea-note-tags note)
                                           vulpea-para-open-work-tags)))))
      (push (vulpea-note-path note) paths))
    (when vulpea-para-open-work-files
      (dolist (note (vulpea-db-query-by-level 0))
        (when (vulpea-para--open-work-path-p (vulpea-note-path note))
          (push (vulpea-note-path note) paths))))
    (setq paths (seq-remove (lambda (path) (gethash path tagged))
                            (seq-uniq paths)))
    (when (and paths vulpea-para-agenda-files-filter)
      (let ((rejected (make-hash-table :test 'equal)))
        (dolist (note (vulpea-db-query-by-file-paths paths 0))
          (unless (funcall vulpea-para-agenda-files-filter note)
            (puthash (vulpea-note-path note) t rejected)))
        (setq paths (seq-remove (lambda (path) (gethash path rejected))
                                paths))))
    paths))

;;;###autoload
(defun vulpea-para-agenda-backfill ()
  "Add the agenda tag to the files that hold open work without it.

Visits each file `vulpea-para-agenda-missing-files' reports, re-runs
the save-time open-work check there, and saves the ones that change,
so a stale database row never mis-tags a file.  A file already open in
a modified buffer is tagged but not saved, so none of your unsaved
edits are committed behind your back.

This is the onboarding command for a vault that predates
`vulpea-para-agenda-mode': run it once and the agenda catches up."
  (interactive)
  (let ((paths (vulpea-para-agenda-missing-files))
        (tagged 0))
    (if (null paths)
        (message "vulpea-para: the agenda is not missing any files")
      (dolist (path paths)
        (let* ((existing (find-buffer-visiting path))
               (buffer (or existing (find-file-noselect path))))
          (with-current-buffer buffer
            (let ((modified (buffer-modified-p)))
              (vulpea-para-update-agenda-tag)
              (when (and (buffer-modified-p) (not modified))
                (save-buffer)
                (setq tagged (1+ tagged)))))
          (unless existing
            (kill-buffer buffer))))
      (message "vulpea-para: tagged %d of %d file%s missing from the agenda"
               tagged (length paths) (if (= (length paths) 1) "" "s")))))

(defcustom vulpea-para-agenda-warn-missing t
  "Non-nil means check once per session for files the agenda is missing.

The agenda only scans files carrying the agenda tag, and the tag is
maintained on save, so open work that was last saved without
`vulpea-para-agenda-mode' never shows up.  When this is non-nil, the
first agenda build of a session looks for such files in the database (a
fast query, no file visits) and suggests `vulpea-para-agenda-backfill'
when it finds any.  Set to nil to keep the agenda quiet about it."
  :type 'boolean
  :group 'vulpea-para)

(defvar vulpea-para-agenda--warned-missing nil
  "Non-nil after the once-per-session missing-files check has run.

Reset when `vulpea-para-agenda-mode' is turned on, so re-enabling the
mode re-arms the check.")

(defun vulpea-para-agenda--warn-missing ()
  "Warn, once per session, about files the agenda is missing.

See `vulpea-para-agenda-warn-missing'."
  (when (and vulpea-para-agenda-warn-missing
             (not vulpea-para-agenda--warned-missing))
    (setq vulpea-para-agenda--warned-missing t)
    (when-let* ((missing (vulpea-para-agenda-missing-files)))
      (display-warning
       'vulpea-para
       (format "%d file%s with open work %s missing from the agenda (no agenda tag); run M-x vulpea-para-agenda-backfill to catch up"
               (length missing)
               (if (= 1 (length missing)) "" "s")
               (if (= 1 (length missing)) "is" "are"))))))

;;; Agenda predicates (operate on the heading at point)
;;
;; These are the building blocks for org-agenda skip functions and
;; custom commands.  They read the heading at point, not a vulpea-note,
;; and key off `vulpea-para-project-tag' so they track your real tag.

(defun vulpea-para-agenda-project-p ()
  "Return non-nil when the heading at point is a project.

A project is a heading that has a todo keyword and is tagged with
`vulpea-para-project-tag'."
  (let* ((comps (org-heading-components))
         (todo (nth 2 comps))
         (tags (split-string (or (nth 5 comps) "") ":" t)))
    (and (member todo org-todo-keywords-1)
         (member vulpea-para-project-tag tags))))

(defun vulpea-para-agenda-find-project-task ()
  "Move point to the parent project task, if any, and return its position."
  (save-restriction
    (widen)
    (let ((parent-task (save-excursion
                         (org-back-to-heading 'invisible-ok)
                         (point))))
      (while (org-up-heading-safe)
        (when (member (nth 2 (org-heading-components)) org-todo-keywords-1)
          (setq parent-task (point))))
      (goto-char parent-task)
      parent-task)))

(defun vulpea-para-agenda-project-subtree-p ()
  "Return non-nil when point is inside a project subtree.

The project task itself does not count; this is for the tasks under
it.  Callers are expected to have widened the buffer."
  (let ((task (save-excursion (org-back-to-heading 'invisible-ok) (point))))
    (save-excursion
      (vulpea-para-agenda-find-project-task)
      (not (equal (point) task)))))

(defun vulpea-para-agenda-task-p ()
  "Return non-nil when the heading at point is a task with no subtask."
  (save-restriction
    (widen)
    (let ((has-subtask)
          (subtree-end (save-excursion (org-end-of-subtree t)))
          (is-a-task (member (nth 2 (org-heading-components))
                             org-todo-keywords-1)))
      (save-excursion
        (forward-line 1)
        (while (and (not has-subtask)
                    (< (point) subtree-end)
                    (re-search-forward "^\\*+ " subtree-end t))
          (when (member (org-get-todo-state) org-todo-keywords-1)
            (setq has-subtask t))))
      (and is-a-task (not has-subtask)))))

;;; Agenda category

(defun vulpea-para-agenda-category (&optional len)
  "Return the agenda category of the item at point.

The category is the first available of: the note's \"short name\"
metadata or TITLE keyword (when it differs from the bare file name),
else the org CATEGORY.  When LEN is a number, the result is padded with
spaces and truncated to LEN with an ellipsis.

Handy in `org-agenda-prefix-format', for example:

  (setq org-agenda-prefix-format
        \\='((agenda . \" %(vulpea-para-agenda-category 36) %?-12t %12s\")))"
  (if (eq major-mode 'org-mode)
      (let* ((file-name (when buffer-file-name
                          (file-name-sans-extension
                           (file-name-nondirectory buffer-file-name))))
             (title (or (vulpea-buffer-meta-get! (vulpea-buffer-meta) "short name")
                        (vulpea-buffer-prop-get "title")))
             (category (org-get-category))
             (result (or (if (and title (string-equal category file-name))
                             title
                           category)
                         "")))
        (if (numberp len)
            (truncate-string-to-width
             (concat result
                     (make-string (max 0 (- len (length result))) ?\s))
             len nil nil "...")
          result))
    (make-string (or len 0) ?\s)))

(defun vulpea-para-agenda-current-quarter (time)
  "Return the quarter of TIME as a string like \"25Q1\"."
  (let* ((decoded (decode-time time))
         (year (nth 5 decoded))
         (month (nth 4 decoded))
         (yy (mod year 100))
         (quarter (cond ((<= month 3) "Q1")
                        ((<= month 6) "Q2")
                        ((<= month 9) "Q3")
                        (t "Q4"))))
    (format "%02d%s" yy quarter)))

(declare-function vulpea-db-sync-tracked-file-p "vulpea-db-sync" (path))

(defun vulpea-para-vault-buffer-p ()
  "Return non-nil when the current buffer visits a file in your vault.

A file is in the vault when it lives under one of
`vulpea-db-sync-directories'.  This is the default scope for
`vulpea-para-agenda-mode', so Org files you edit outside your notes are
never touched.

Delegates to `vulpea-db-sync-tracked-file-p' when the installed vulpea
provides it (that is the single source of truth, and resolves symlinks
on both sides so a vault reached through a link still matches).  On an
older vulpea it falls back to the same `file-truename' comparison
inline, so the check keeps working without requiring a vulpea upgrade."
  (when-let* ((file (buffer-file-name)))
    (if (fboundp 'vulpea-db-sync-tracked-file-p)
        (vulpea-db-sync-tracked-file-p file)
      (when-let* ((dirs (bound-and-true-p vulpea-db-sync-directories)))
        (let ((file (file-truename file)))
          (seq-some
           (lambda (dir)
             (string-prefix-p (file-name-as-directory (file-truename dir))
                              file))
           dirs))))))

(defcustom vulpea-para-agenda-tag-scope #'vulpea-para-vault-buffer-p
  "Predicate choosing which buffers `vulpea-para-agenda-mode' tags on save.

Called with no arguments in the buffer about to be saved; non-nil means
maintain the agenda tag here.  The default, `vulpea-para-vault-buffer-p',
limits tagging to files in your vulpea vault, so Org files elsewhere
never pick up an agenda tag.  To tag every Org buffer instead, set this
to a function that always returns non-nil."
  :type 'function
  :group 'vulpea-para)

(defun vulpea-para--maybe-update-agenda-tag ()
  "Update the agenda tag, subject to `vulpea-para-agenda-tag-scope'.

This is what `vulpea-para-agenda-mode' runs on `before-save-hook'."
  (when (funcall vulpea-para-agenda-tag-scope)
    (vulpea-para-update-agenda-tag)))

(defun vulpea-para--install-save-hook ()
  "Install the agenda-tag updater on save in the current buffer."
  (add-hook 'before-save-hook #'vulpea-para--maybe-update-agenda-tag nil t))

;;;###autoload
(define-minor-mode vulpea-para-agenda-mode
  "Keep the PARA agenda fast and self-updating.

When on, Org buffers in your vault maintain their agenda tag on save, and
`org-agenda-files' is refreshed from the database before each agenda or
todo list is built.  The tagging scope is `vulpea-para-agenda-tag-scope',
which limits it to your vault by default so files elsewhere are left
alone.  You wire this up once; after that a file slips in and out of the
agenda on its own as work appears and finishes."
  :global t
  :group 'vulpea-para
  (if vulpea-para-agenda-mode
      (progn
        (setq vulpea-para-agenda--warned-missing nil)
        (add-hook 'org-mode-hook #'vulpea-para--install-save-hook)
        (advice-add 'org-agenda :before #'vulpea-para-agenda-files-update)
        (advice-add 'org-todo-list :before #'vulpea-para-agenda-files-update))
    (remove-hook 'org-mode-hook #'vulpea-para--install-save-hook)
    (advice-remove 'org-agenda #'vulpea-para-agenda-files-update)
    (advice-remove 'org-todo-list #'vulpea-para-agenda-files-update)))

;;; Agenda commands and the pieces they are built from
;;
;; vulpea-para never sets `org-agenda-custom-commands' or any other org
;; variable.  It ships these as building blocks; you assemble them in
;; your own config.  See the README for an example value.  The command
;; building blocks assume the tag and todo-keyword conventions described
;; there (a lowercase project tag plus FOCUS / WAITING / HOLD /
;; CANCELLED / REFILE).

(defcustom vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks t
  "Non-nil means hide scheduled and waiting tasks in some agenda commands.

Affects `vulpea-para-agenda-cmd-focus', `vulpea-para-agenda-cmd-waiting',
and `vulpea-para-agenda-cmd-current-quarter'."
  :type 'boolean
  :group 'vulpea-para)

(defcustom vulpea-para-agenda-main-key " "
  "Key of the custom command opened by `vulpea-para-agenda-main'.

You define that command in your own `org-agenda-custom-commands'."
  :type 'string
  :group 'vulpea-para)

(defcustom vulpea-para-agenda-main-buffer-name "*PARA agenda*"
  "Buffer name for the agenda built by `vulpea-para-setup-defaults'.

The dispatcher that `vulpea-para-setup-defaults' installs binds
`org-agenda-buffer-name' to this, so the main agenda gets a stable,
recognizable name instead of the shared `*Org Agenda*'.  Set it before
calling `vulpea-para-setup-defaults' to use your own."
  :type 'string
  :group 'vulpea-para)

;;;; Skip functions (for `org-agenda-skip-function')

(defun vulpea-para-agenda-skip-habits ()
  "Skip tasks that are habits."
  (save-restriction
    (widen)
    (let ((subtree-end (save-excursion (org-end-of-subtree t))))
      (if (org-is-habit-p) subtree-end nil))))

(defun vulpea-para-agenda-skip-non-stuck-projects ()
  "Skip trees that are not stuck projects.

A stuck project has subtasks but no actionable (non-WAITING) next task."
  (save-restriction
    (widen)
    (let ((next-headline (save-excursion (or (outline-next-heading) (point-max)))))
      (if (vulpea-para-agenda-project-p)
          (let ((subtree-end (save-excursion (org-end-of-subtree t)))
                (has-next))
            (save-excursion
              (forward-line 1)
              (while (and (not has-next)
                          (< (point) subtree-end)
                          (re-search-forward "^\\*+ TODO " subtree-end t))
                (unless (member "WAITING" (org-get-tags))
                  (setq has-next t))))
            (if has-next next-headline nil))
        next-headline))))

(defun vulpea-para-agenda-skip-non-projects ()
  "Skip trees that are not projects."
  (if (save-excursion (vulpea-para-agenda-skip-non-stuck-projects))
      (save-restriction
        (widen)
        (let ((subtree-end (save-excursion (org-end-of-subtree t))))
          (cond
           ((vulpea-para-agenda-project-p) nil)
           ((and (vulpea-para-agenda-project-subtree-p)
                 (not (vulpea-para-agenda-task-p)))
            nil)
           (t subtree-end))))
    (save-excursion (org-end-of-subtree t))))

(defun vulpea-para-agenda-skip-non-tasks ()
  "Skip everything that is not a plain task.

Skips projects, sub-project tasks, and habits."
  (save-restriction
    (widen)
    (let ((next-headline (save-excursion (or (outline-next-heading) (point-max)))))
      (if (vulpea-para-agenda-task-p) nil next-headline))))

;;;; Custom command building blocks
;;
;; Splice these into your own `org-agenda-custom-commands'.

;;;###autoload
(defconst vulpea-para-agenda-cmd-refile
  '(tags
    "REFILE"
    ((org-agenda-overriding-header "To refile")
     (org-tags-match-list-sublevels t)
     (org-agenda-skip-function 'vulpea-para-agenda-skip-non-tasks)))
  "Agenda block listing items tagged REFILE.")

;;;###autoload
(defconst vulpea-para-agenda-cmd-today
  '(agenda
    ""
    ((org-agenda-span 'day)
     (org-agenda-skip-deadline-prewarning-if-scheduled t)
     (org-agenda-sorting-strategy '(habit-down time-up category-keep
                                    todo-state-down priority-down))))
  "Agenda block for today.")

;;;###autoload
(defconst vulpea-para-agenda-cmd-focus
  '(tags-todo
    "FOCUS"
    ((org-agenda-overriding-header "To focus on")
     (org-agenda-skip-function 'vulpea-para-agenda-skip-habits)
     (org-tags-match-list-sublevels t)
     (org-agenda-todo-ignore-scheduled
      vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks)
     (org-agenda-todo-ignore-deadlines
      vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks)
     (org-agenda-todo-ignore-with-date
      vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks)
     (org-agenda-tags-todo-honor-ignore-options t)
     (org-agenda-sorting-strategy
      '(todo-state-down priority-down effort-up category-keep))))
  "Agenda block for items tagged FOCUS.")

;;;###autoload
(defconst vulpea-para-agenda-cmd-stuck-projects
  '(tags-todo
    "project-CANCELLED-HOLD/!"
    ((org-agenda-overriding-header "Stuck Projects")
     (org-agenda-skip-function 'vulpea-para-agenda-skip-non-stuck-projects)
     (org-agenda-sorting-strategy
      '(todo-state-down priority-down effort-up category-keep))))
  "Agenda block for stuck projects (a project with no next action).")

;;;###autoload
(defconst vulpea-para-agenda-cmd-projects
  '(tags-todo
    "project-HOLD"
    ((org-agenda-overriding-header "Projects")
     (org-tags-match-list-sublevels t)
     (org-agenda-skip-function 'vulpea-para-agenda-skip-non-projects)
     (org-agenda-tags-todo-honor-ignore-options t)
     (org-agenda-sorting-strategy
      '(todo-state-down priority-down effort-up category-keep))))
  "Agenda block for all projects.")

(defconst vulpea-para-agenda-cmd-waiting
  '(tags-todo
    "-CANCELLED+WAITING-FOCUS|+HOLD/!"
    ((org-agenda-overriding-header "Waiting and Postponed Tasks")
     (org-agenda-skip-function 'vulpea-para-agenda-skip-non-tasks)
     (org-tags-match-list-sublevels nil)
     (org-agenda-todo-ignore-scheduled
      vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks)
     (org-agenda-todo-ignore-deadlines
      vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks)))
  "Agenda block for waiting and postponed tasks.")

;;;###autoload
(defun vulpea-para-agenda-cmd-current-quarter ()
  "Return an agenda block for the current quarter's tasks."
  (let ((quarter (vulpea-para-agenda-current-quarter (current-time))))
    `(tags-todo
      ,quarter
      ((org-agenda-overriding-header (concat "Tasks for " ,quarter))
       (org-agenda-skip-function 'vulpea-para-agenda-skip-habits)
       (org-tags-match-list-sublevels t)
       (org-agenda-todo-ignore-scheduled
        vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks)
       (org-agenda-todo-ignore-deadlines
        vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks)
       (org-agenda-todo-ignore-with-date
        vulpea-para-agenda-hide-scheduled-and-waiting-next-tasks)
       (org-agenda-tags-todo-honor-ignore-options t)
       (org-agenda-sorting-strategy
        '(todo-state-down priority-down effort-up category-keep))))))

;;;; Commands

(defun vulpea-para-agenda--title-to-tag (title)
  "Convert a person's TITLE to the tag used on tasks about them."
  (concat "@" (replace-regexp-in-string " " "" title)))

;;;###autoload
(defun vulpea-para-agenda-main ()
  "Open the main agenda, the `vulpea-para-agenda-main-key' custom command.

You define that command in your own `org-agenda-custom-commands'."
  (interactive)
  (org-agenda nil vulpea-para-agenda-main-key))

;;;###autoload
(defun vulpea-para-agenda-person ()
  "Show a tags-todo agenda for a selected person.

Matches tasks tagged with the person's name or any alias.  People are
the notes tagged with `vulpea-para-people-tag'."
  (interactive)
  (let* ((person (vulpea-select-from
                  "Person"
                  (vulpea-db-query-by-tags-some
                   (list vulpea-para-people-tag))
                  :require-match t))
         (names (cons (vulpea-note-title person)
                      (vulpea-note-aliases person)))
         (query (string-join
                 (mapcar #'vulpea-para-agenda--title-to-tag names) "|"))
         (org-agenda-overriding-arguments (list t query)))
    (org-agenda nil "M")))

;;;###autoload
(defun vulpea-para-agenda-area ()
  "Show a TODO agenda restricted to a selected area's file.

`org-agenda-files' is bound to the area's file only for the duration of
the command; nothing is set permanently.  The agenda-mode files update
is inhibited so it does not widen the scope back to every agenda file."
  (interactive)
  (let* ((area (vulpea-select-from "Area" (vulpea-para-areas)
                                   :require-match t))
         (org-agenda-files (list (vulpea-note-path area)))
         (vulpea-para-agenda-inhibit-files-update t))
    (org-agenda nil "t")))

(provide 'vulpea-para-agenda)
;;; vulpea-para-agenda.el ends here
