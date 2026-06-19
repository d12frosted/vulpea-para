;;; vulpea-para-test.el --- Tests for vulpea-para -*- lexical-binding: t; -*-
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
;; Tests for vulpea-para.
;;
;; The bucket predicates are pure functions of a `vulpea-note', so the
;; tests build notes by hand and do not need a database.
;;
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'vulpea-para)
(require 'vulpea-para-test-helpers)

;;; Bucket predicates

(ert-deftest vulpea-para-area-p-test ()
  "An area is a file-level note tagged `area', and nothing else is."
  ;; a whole file carrying the area tag
  (should (vulpea-para-area-p
           (make-vulpea-note :level 0 :tags '("area"))))
  ;; area among several tags is still an area
  (should (vulpea-para-area-p
           (make-vulpea-note :level 0 :tags '("agenda" "area"))))
  ;; a heading tagged area is not an area; areas are whole files
  (should-not (vulpea-para-area-p
               (make-vulpea-note :level 1 :tags '("area"))))
  ;; a file with some other role is not an area
  (should-not (vulpea-para-area-p
               (make-vulpea-note :level 0 :tags '("people")))))

(ert-deftest vulpea-para-project-p-test ()
  "A project is a heading tagged `project', and a file never is."
  ;; a heading carrying the project tag
  (should (vulpea-para-project-p
           (make-vulpea-note :level 1 :tags '("project"))))
  ;; deeper heading, project among several tags
  (should (vulpea-para-project-p
           (make-vulpea-note :level 2 :tags '("project" "area"))))
  ;; a whole file tagged project is not a project; projects are headings
  (should-not (vulpea-para-project-p
               (make-vulpea-note :level 0 :tags '("project"))))
  ;; a plain heading is not a project
  (should-not (vulpea-para-project-p
               (make-vulpea-note :level 1 :tags '("task")))))

(ert-deftest vulpea-para-archived-p-test ()
  "Archived is the org archive tag or an ARCHIVE_TIME property."
  ;; an ARCHIVE_TIME property marks an archived note
  (should (vulpea-para-archived-p
           (make-vulpea-note :level 1
                             :properties '(("ARCHIVE_TIME" . "2025-01-24 Fri")))))
  ;; the org archive tag marks an archived note
  (should (vulpea-para-archived-p
           (make-vulpea-note :level 1 :tags '("ARCHIVE"))))
  ;; a plain note is not archived
  (should-not (vulpea-para-archived-p
               (make-vulpea-note :level 1 :tags '("project"))))
  ;; a DONE state on its own is not "archived"
  (should-not (vulpea-para-archived-p
               (make-vulpea-note :level 1 :todo "DONE"))))

(ert-deftest vulpea-para-resource-p-test ()
  "A resource is a file-level note that has not been archived."
  ;; any file-level reference note
  (should (vulpea-para-resource-p
           (make-vulpea-note :level 0 :tags '("people"))))
  ;; an area is a resource too (facets, not walls)
  (should (vulpea-para-resource-p
           (make-vulpea-note :level 0 :tags '("area"))))
  ;; a heading is not a resource
  (should-not (vulpea-para-resource-p
               (make-vulpea-note :level 1 :tags '("project"))))
  ;; an archived file-level note is not an active resource
  (should-not (vulpea-para-resource-p
               (make-vulpea-note :level 0 :tags '("ARCHIVE")))))

(ert-deftest vulpea-para-note-buckets-test ()
  "A note reports every bucket it belongs to, possibly more than one."
  ;; an area file is both an area and a resource
  (should (equal '(area resource)
                 (vulpea-para-note-buckets
                  (make-vulpea-note :level 0 :tags '("area")))))
  ;; a project heading is just a project
  (should (equal '(project)
                 (vulpea-para-note-buckets
                  (make-vulpea-note :level 1 :tags '("project")))))
  ;; a plain file note is a resource
  (should (equal '(resource)
                 (vulpea-para-note-buckets
                  (make-vulpea-note :level 0 :tags '("people")))))
  ;; an archived note reports the archive bucket
  (should (equal '(archive)
                 (vulpea-para-note-buckets
                  (make-vulpea-note :level 1
                                    :properties '(("ARCHIVE_TIME" . "x")))))))

;;; Database-backed queries

(ert-deftest vulpea-para-areas-test ()
  "Only file-level area notes come back as areas."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "area1" "Blog" :level 0 :tags '("agenda" "area"))
    (vulpea-para-test--insert "res1" "A Person" :level 0 :tags '("people"))
    (vulpea-para-test--insert "proj1" "Ship it" :level 1 :tags '("project")
                              :path "/tmp/area1.org")
    (should (equal '("Blog")
                   (mapcar #'vulpea-note-title (vulpea-para-areas))))))

(ert-deftest vulpea-para-projects-test ()
  "Only heading-level project notes come back as projects."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "area1" "Blog" :level 0 :tags '("area"))
    (vulpea-para-test--insert "proj1" "Ship v2.1" :level 1 :tags '("project"))
    (vulpea-para-test--insert "proj2" "Fix RSS" :level 2 :tags '("project"))
    (should (equal '("Fix RSS" "Ship v2.1")
                   (sort (mapcar #'vulpea-note-title (vulpea-para-projects))
                         #'string<)))))

(ert-deftest vulpea-para-resources-test ()
  "Resources are the file-level notes, areas included."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "area1" "Blog" :level 0 :tags '("area"))
    (vulpea-para-test--insert "res1" "A Person" :level 0 :tags '("people"))
    (vulpea-para-test--insert "proj1" "Ship it" :level 1 :tags '("project"))
    (should (equal '("A Person" "Blog")
                   (sort (mapcar #'vulpea-note-title (vulpea-para-resources))
                         #'string<)))))

(ert-deftest vulpea-para-area-of-test ()
  "A note's area is the area note of the file it lives in."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "blog" "Blog" :level 0 :tags '("area")
                              :path "/tmp/blog.org")
    (vulpea-para-test--insert "proj1" "Ship v2.1" :level 1 :tags '("project")
                              :path "/tmp/blog.org")
    (vulpea-para-test--insert "loose" "Loose" :level 1 :tags '("project")
                              :path "/tmp/loose.org")
    (should (equal "Blog"
                   (vulpea-note-title
                    (vulpea-para-area-of (vulpea-db-get-by-id "proj1")))))
    ;; a project in a file with no area note has no area
    (should-not (vulpea-para-area-of (vulpea-db-get-by-id "loose")))))

(ert-deftest vulpea-para-projects-in-area-test ()
  "Projects in an area are the project headings in the area's file."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "blog" "Blog" :level 0 :tags '("area")
                              :path "/tmp/blog.org")
    (vulpea-para-test--insert "proj1" "Ship v2.1" :level 1 :tags '("project")
                              :path "/tmp/blog.org")
    (vulpea-para-test--insert "proj2" "Elsewhere" :level 1 :tags '("project")
                              :path "/tmp/other.org")
    (should (equal '("Ship v2.1")
                   (mapcar #'vulpea-note-title
                           (vulpea-para-projects-in-area
                            (vulpea-db-get-by-id "blog")))))))

;;; Agenda

(ert-deftest vulpea-para-buffer-open-work-p-test ()
  "Open work is a not-done TODO heading somewhere in the buffer."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: A\n\n* TODO do it\n")
    (should (vulpea-para-buffer-open-work-p)))
  (with-temp-buffer
    (org-mode)
    (insert "#+title: A\n\n* DONE done\n* a plain heading\n")
    (should-not (vulpea-para-buffer-open-work-p)))
  (with-temp-buffer
    (org-mode)
    (insert "#+title: A\n\njust prose, no headings\n")
    (should-not (vulpea-para-buffer-open-work-p))))

(ert-deftest vulpea-para-buffer-open-work-p-extras-test ()
  "A force tag or an active timestamp also counts as open work."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: A\n\n* A note :REFILE:\n")
    (should (vulpea-para-buffer-open-work-p)))
  (with-temp-buffer
    (org-mode)
    (insert "#+title: A\n\n* A note\n<2025-06-20 Fri>\n")
    (should (vulpea-para-buffer-open-work-p))))

(ert-deftest vulpea-para-update-agenda-tag-test ()
  "The agenda tag is added or dropped to match the file's open work."
  ;; open work, no tag yet -> tag is added
  (with-temp-buffer
    (org-mode)
    (insert "#+title: A\n\n* TODO do it\n")
    (vulpea-para-update-agenda-tag)
    (goto-char (point-min))
    (should (member "agenda" (vulpea-buffer-tags-get t))))
  ;; no open work, tag present -> only the agenda tag is removed
  (with-temp-buffer
    (org-mode)
    (insert "#+title: A\n#+filetags: :agenda:area:\n\n* DONE done\n")
    (vulpea-para-update-agenda-tag)
    (goto-char (point-min))
    (let ((tags (vulpea-buffer-tags-get t)))
      (should-not (member "agenda" tags))
      (should (member "area" tags)))))

(ert-deftest vulpea-para-vault-buffer-p-test ()
  "Only files under `vulpea-db-sync-directories' count as vault buffers."
  (let ((vulpea-db-sync-directories (list "/tmp/vault")))
    ;; a file inside the vault
    (with-temp-buffer
      (setq buffer-file-name "/tmp/vault/note.org")
      (should (vulpea-para-vault-buffer-p)))
    ;; a sibling that merely shares a name prefix is not the vault
    (with-temp-buffer
      (setq buffer-file-name "/tmp/vault-of-doom/note.org")
      (should-not (vulpea-para-vault-buffer-p)))
    ;; a file somewhere else entirely
    (with-temp-buffer
      (setq buffer-file-name "/tmp/elsewhere/readme.org")
      (should-not (vulpea-para-vault-buffer-p)))
    ;; a buffer with no file at all
    (with-temp-buffer
      (should-not (vulpea-para-vault-buffer-p))))
  ;; with no vault configured, nothing counts as in the vault
  (let ((vulpea-db-sync-directories nil))
    (with-temp-buffer
      (setq buffer-file-name "/tmp/vault/note.org")
      (should-not (vulpea-para-vault-buffer-p)))))

(ert-deftest vulpea-para-maybe-update-agenda-tag-scope-test ()
  "The save-time updater only tags buffers the scope predicate accepts."
  ;; scope rejects the buffer -> no agenda tag even with open work
  (let ((vulpea-para-agenda-tag-scope #'ignore))
    (with-temp-buffer
      (org-mode)
      (insert "#+title: A\n\n* TODO do it\n")
      (vulpea-para--maybe-update-agenda-tag)
      (goto-char (point-min))
      (should-not (member "agenda" (vulpea-buffer-tags-get t)))))
  ;; scope accepts the buffer -> the tag is maintained as usual
  (let ((vulpea-para-agenda-tag-scope (lambda () t)))
    (with-temp-buffer
      (org-mode)
      (insert "#+title: A\n\n* TODO do it\n")
      (vulpea-para--maybe-update-agenda-tag)
      (goto-char (point-min))
      (should (member "agenda" (vulpea-buffer-tags-get t))))))

(ert-deftest vulpea-para-agenda-files-test ()
  "Agenda files are the paths of notes carrying the agenda tag."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "a1" "Blog" :level 0 :tags '("agenda" "area")
                              :path "/tmp/blog.org")
    (vulpea-para-test--insert "a2" "Garden" :level 0 :tags '("area")
                              :path "/tmp/garden.org")
    (should (equal '("/tmp/blog.org") (vulpea-para-agenda-files)))))

(ert-deftest vulpea-para-agenda-files-update-test ()
  "Updating sets `org-agenda-files' to the agenda-tagged files."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "a1" "Blog" :level 0 :tags '("agenda")
                              :path "/tmp/blog.org")
    (let ((org-agenda-files nil))
      (vulpea-para-agenda-files-update)
      (should (equal '("/tmp/blog.org") org-agenda-files)))))

(ert-deftest vulpea-para-agenda-files-update-inhibit-test ()
  "Updating is a no-op while `vulpea-para-agenda-inhibit-files-update'.

This is what keeps `vulpea-para-agenda-area' scoped to one file even
though the agenda-mode advice runs on every `org-agenda' call."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "a1" "Blog" :level 0 :tags '("agenda")
                              :path "/tmp/blog.org")
    (let ((org-agenda-files '("/tmp/area.org"))
          (vulpea-para-agenda-inhibit-files-update t))
      (vulpea-para-agenda-files-update)
      (should (equal '("/tmp/area.org") org-agenda-files)))))

;;; Capture

(ert-deftest vulpea-para-category-test ()
  "A project's category reads as \"Area > Project\"."
  (should (equal "Blog > Ship v2.1"
                 (vulpea-para-category "Blog" "Ship v2.1"))))

(ert-deftest vulpea-para-capture-area-test ()
  "Capturing an area asks for an area-tagged note seeded with the body."
  (let (captured)
    (cl-letf (((symbol-function 'vulpea-create)
               (lambda (title _file-name &rest args)
                 (setq captured args)
                 (make-vulpea-note :title title :level 0
                                   :tags (plist-get args :tags))))
              ((symbol-function 'vulpea-visit) #'ignore))
      (let ((note (vulpea-para-capture-area "Garden" :no-visit)))
        (should (vulpea-para-area-p note))
        (should (member "area" (plist-get captured :tags)))
        (should (string-match-p "Tasks" (plist-get captured :body)))))))

(ert-deftest vulpea-para-capture-project-test ()
  "Capturing a project drops a tagged, categorized heading under Tasks."
  (let ((file (make-temp-file
               "vp-area-" nil ".org"
               (concat ":PROPERTIES:\n:ID: area-1\n:END:\n"
                       "#+title: Blog\n#+filetags: :area:\n\n* Tasks\n"))))
    (unwind-protect
        (let* ((area (make-vulpea-note :path file :title "Blog" :level 0
                                       :tags '("area")))
               (id (vulpea-para-capture-project area "Ship v2.1")))
          (should (stringp id))
          (with-temp-buffer
            (insert-file-contents file)
            (let ((s (buffer-string)))
              (should (string-match-p "^\\*\\* TODO Ship v2.1 +:project:$" s))
              (should (string-match-p ":CATEGORY: Blog > Ship v2.1" s))
              (should (string-match-p (concat ":ID:[ \t]+" (regexp-quote id)) s)))))
      (when (get-file-buffer file) (kill-buffer (get-file-buffer file)))
      (delete-file file))))

(ert-deftest vulpea-para-capture-project-creates-tasks-test ()
  "Capturing into an area with no Tasks heading creates one."
  (let ((file (make-temp-file
               "vp-area-" nil ".org"
               (concat ":PROPERTIES:\n:ID: area-2\n:END:\n"
                       "#+title: Garden\n#+filetags: :area:\n"))))
    (unwind-protect
        (let ((area (make-vulpea-note :path file :title "Garden" :level 0
                                      :tags '("area"))))
          (vulpea-para-capture-project area "Plant tomatoes")
          (with-temp-buffer
            (insert-file-contents file)
            (let ((s (buffer-string)))
              (should (string-match-p "^\\* Tasks$" s))
              (should (string-match-p "^\\*\\* TODO Plant tomatoes +:project:$" s)))))
      (when (get-file-buffer file) (kill-buffer (get-file-buffer file)))
      (delete-file file))))

;;; Doctor

(ert-deftest vulpea-para-doctor-orphan-projects-test ()
  "Orphan projects are projects in a file with no area note."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "blog" "Blog" :level 0 :tags '("area")
                              :path "/tmp/blog.org")
    (vulpea-para-test--insert "p1" "In area" :level 1 :tags '("project")
                              :path "/tmp/blog.org")
    (vulpea-para-test--insert "p2" "Orphan" :level 1 :tags '("project")
                              :path "/tmp/loose.org")
    (should (equal '("Orphan")
                   (mapcar #'vulpea-note-title
                           (vulpea-para-doctor-orphan-projects))))))

(ert-deftest vulpea-para-doctor-stale-agenda-files-test ()
  "Stale agenda files carry the tag but hold no open task."
  (vulpea-para-test--with-temp-db
    ;; f1: tagged, has an open TODO -> not stale
    (vulpea-para-test--insert "a1" "F1" :level 0 :tags '("agenda")
                              :path "/tmp/f1.org")
    (vulpea-para-test--insert "h1" "do it" :level 1 :todo "TODO"
                              :path "/tmp/f1.org")
    ;; f2: tagged, only a DONE task -> stale
    (vulpea-para-test--insert "a2" "F2" :level 0 :tags '("agenda")
                              :path "/tmp/f2.org")
    (vulpea-para-test--insert "h2" "did it" :level 1 :todo "DONE"
                              :path "/tmp/f2.org")
    ;; f3: tagged, no tasks at all -> stale
    (vulpea-para-test--insert "a3" "F3" :level 0 :tags '("agenda")
                              :path "/tmp/f3.org")
    (should (equal '("/tmp/f2.org" "/tmp/f3.org")
                   (sort (vulpea-para-doctor-stale-agenda-files) #'string<)))))

;;; Archive

(ert-deftest vulpea-para-archive-project-test ()
  "Archiving a project moves it under the file's Archive subtree."
  (let ((file (make-temp-file
               "vp-area-" nil ".org"
               (concat ":PROPERTIES:\n:ID: a\n:END:\n"
                       "#+title: Blog\n#+filetags: :area:\n\n"
                       "* Tasks\n"
                       "** DONE Ship it :project:\n"
                       ":PROPERTIES:\n:ID: p1\n:END:\n"))))
    (unwind-protect
        (let (pos)
          (with-current-buffer (find-file-noselect file)
            (goto-char (point-min))
            (re-search-forward "^\\*\\* DONE Ship it")
            (setq pos (line-beginning-position))
            (kill-buffer))
          (vulpea-para-archive-project
           (make-vulpea-note :path file :id "p1" :title "Ship it" :level 2
                             :pos pos :tags '("project")))
          (with-temp-buffer
            (insert-file-contents file)
            (let ((s (buffer-string)))
              ;; an Archive heading tagged :ARCHIVE: now exists, so the whole
              ;; archived subtree leaves vulpea's active database
              (should (string-match-p "^\\* Archive.*:ARCHIVE:" s))
              ;; the project was recorded as archived, moved out of Tasks
              (should (string-match-p ":ARCHIVE_TIME:" s))
              (should (string-match-p ":ARCHIVE_OLPATH: Tasks" s))
              (should (string-match-p "Ship it" s)))))
      (when (get-file-buffer file) (kill-buffer (get-file-buffer file)))
      (delete-file file))))

;;; Agenda primitives

(ert-deftest vulpea-para-agenda-project-p-test ()
  "A project heading has a todo keyword and the project tag."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Build it :project:\n")
    (goto-char (point-min))
    (should (vulpea-para-agenda-project-p)))
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Build it\n")
    (goto-char (point-min))
    (should-not (vulpea-para-agenda-project-p)))
  (with-temp-buffer
    (org-mode)
    (insert "* Build it :project:\n")
    (goto-char (point-min))
    (should-not (vulpea-para-agenda-project-p))))

(ert-deftest vulpea-para-agenda-task-p-test ()
  "A task has a todo keyword and no todo subtask."
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Simple task\n")
    (goto-char (point-min))
    (should (vulpea-para-agenda-task-p)))
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Parent\n** TODO Child\n")
    (goto-char (point-min))
    (should-not (vulpea-para-agenda-task-p)))
  (with-temp-buffer
    (org-mode)
    (insert "* Just a heading\n")
    (goto-char (point-min))
    (should-not (vulpea-para-agenda-task-p))))

(ert-deftest vulpea-para-agenda-current-quarter-test ()
  "Quarters read as YYQn."
  (should (equal "25Q1" (vulpea-para-agenda-current-quarter
                         (encode-time (list 0 0 0 15 2 2025 nil -1 nil)))))
  (should (equal "25Q4" (vulpea-para-agenda-current-quarter
                         (encode-time (list 0 0 0 15 11 2025 nil -1 nil))))))

(ert-deftest vulpea-para-agenda--title-to-tag-test ()
  "A person's name becomes an @-prefixed, space-stripped tag."
  (should (equal "@BorisBuliga"
                 (vulpea-para-agenda--title-to-tag "Boris Buliga"))))

(ert-deftest vulpea-para-agenda-files-filter-test ()
  "The files filter keeps out notes it rejects."
  (vulpea-para-test--with-temp-db
    (vulpea-para-test--insert "a1" "Blog" :level 0 :tags '("agenda")
                              :path "/tmp/blog.org")
    (vulpea-para-test--insert "a2" "Dead" :level 0 :tags '("agenda" "cemetery")
                              :path "/tmp/dead.org")
    (let ((vulpea-para-agenda-files-filter
           (lambda (n) (not (vulpea-note-tagged-any-p n "cemetery")))))
      (should (equal '("/tmp/blog.org") (vulpea-para-agenda-files))))))

;;; Setup defaults

(ert-deftest vulpea-para-setup-defaults-test ()
  "Setup-defaults installs the agenda commands and capture templates."
  (cl-letf (((symbol-function 'vulpea-para-agenda-mode) #'ignore))
    (let ((vulpea-para-agenda-main-buffer-name "*test agenda*")
          org-agenda-custom-commands
          org-agenda-prefix-format
          org-capture-templates)
      (vulpea-para-setup-defaults)
      (should (assoc " " org-agenda-custom-commands))
      (should (assoc "p" org-capture-templates))
      (should (assoc "m" org-capture-templates))
      (should org-agenda-prefix-format)
      ;; the main command names its buffer from the configurable default
      (should (equal (cadr (assq 'org-agenda-buffer-name
                                 (nth 3 (assoc " " org-agenda-custom-commands))))
                     "*test agenda*"))
      ;; meetings clock in on capture
      (should (plist-get (nthcdr 5 (assoc "m" org-capture-templates))
                         :clock-in))
      (should (plist-get (nthcdr 5 (assoc "m" org-capture-templates))
                         :clock-resume)))))

(provide 'vulpea-para-test)
;;; vulpea-para-test.el ends here
