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

(defcustom vulpea-para-open-work-tags '("REFILE")
  "Tags that always count as open work, whatever the TODO state.

A heading carrying one of these (for example REFILE, something waiting
to be sorted) keeps its file on the agenda even with no open TODO."
  :type '(repeat string)
  :group 'vulpea-para)

(defun vulpea-para-buffer-open-work-p ()
  "Return non-nil when the current buffer holds any open work.

Open work is any of: a not-done TODO heading; a heading tagged with one
of `vulpea-para-open-work-tags'; or a not-done heading carrying an
active timestamp (something with a date still ahead of it).  A buffer
with only DONE or plain headings, or no headings at all, holds none."
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
    nil 'first-match))

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

(defun vulpea-para-agenda-files-update (&rest _)
  "Set `org-agenda-files' to the PARA agenda files.

Ignores its arguments, so it works as :before advice on `org-agenda'
and `org-todo-list'."
  (setq org-agenda-files (vulpea-para-agenda-files)))

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

(defun vulpea-para--install-save-hook ()
  "Install the agenda-tag updater on save in the current buffer."
  (add-hook 'before-save-hook #'vulpea-para-update-agenda-tag nil t))

;;;###autoload
(define-minor-mode vulpea-para-agenda-mode
  "Keep the PARA agenda fast and self-updating.

When on, every Org buffer maintains its agenda tag on save, and
`org-agenda-files' is refreshed from the database before each agenda or
todo list is built.  You wire this up once; after that a file slips in
and out of the agenda on its own as work appears and finishes."
  :global t
  :group 'vulpea-para
  (if vulpea-para-agenda-mode
      (progn
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
the command; nothing is set permanently."
  (interactive)
  (let* ((area (vulpea-select-from "Area" (vulpea-para-areas)
                                   :require-match t))
         (org-agenda-files (list (vulpea-note-path area))))
    (org-agenda nil "t")))

(provide 'vulpea-para-agenda)
;;; vulpea-para-agenda.el ends here
