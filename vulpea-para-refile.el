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
;; That alone is not enough at scale, though.  Org builds its target
;; table by visiting every file in the list, and at a few hundred
;; milliseconds per note file a real vault takes minutes.  The database
;; already knows every heading, its position, and its level, so
;; `vulpea-para-refile-mode' answers `org-refile-get-targets' straight
;; from a query (see `vulpea-para-refile-target-table') whenever
;; `org-refile-targets' is the spec above, and touches no file at all.
;; Any other value of `org-refile-targets', including the let-bound ones
;; org-goto uses, falls through to org's own scan.
;;
;; `vulpea-para-setup-defaults' wires all of this for you.
;;
;;; Code:

(require 'org)
(require 'org-refile)
(require 'seq)
(require 'vulpea-note)
(require 'vulpea-db-query)
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

(defun vulpea-para-refile--file-paths (notes)
  "Order and filter file-level NOTES into refile candidate paths.

Keeps the live (not archived) file-level notes, drops the ones
`vulpea-para-refile-files-filter' rejects, and returns their paths with
area files first so the PARA pillars surface at the top of the target
list."
  (let ((notes (seq-filter #'vulpea-para-resource-p notes)))
    (when vulpea-para-refile-files-filter
      (setq notes (seq-filter vulpea-para-refile-files-filter notes)))
    (seq-uniq
     (append
      (mapcar #'vulpea-note-path (seq-filter #'vulpea-para-area-p notes))
      (mapcar #'vulpea-note-path notes)))))

(defun vulpea-para-refile-files ()
  "Return the file paths of all refile candidate notes.

These are all live (not archived) file-level notes in the vault, with
area files first so the PARA pillars surface at the top of the target
list.  When `vulpea-para-refile-files-filter' is set, notes it rejects
are left out.

Use it as the FILES part of an `org-refile-targets' entry:

  (setq org-refile-targets
        \\='((vulpea-para-refile-files :maxlevel . 3)))"
  (vulpea-para-refile--file-paths (vulpea-db-query-by-level 0)))

(defun vulpea-para-refile-verify-target ()
  "Return non-nil when the heading at point is a valid refile target.

Archived headings are not, and the check moves point past the archived
subtree so its children are never offered either.  Meant for
`org-refile-target-verify-function'."
  (if (member org-archive-tag (org-get-tags))
      (progn (org-end-of-subtree t t) nil)
    t))

;;; The database-backed target table
;;
;; Org builds refile targets by visiting every candidate file, which is
;; hopeless across a whole vault.  Everything org wants in that table
;; (heading text, file, position, level) is already in the database, so
;; we build the same table with one query and no file visits.

(defun vulpea-para-refile--spec-levels (spec)
  "Return the (MIN . MAX) heading levels SPEC asks for, or nil.

SPEC is the SPECIFICATION part of an `org-refile-targets' entry.  Only
the level-based ones can be answered from the database: t, `:maxlevel',
and `:level' (in both the dotted and the plain-list spelling org
accepts).  For anything else, nil: the caller falls back to org's own
file scan."
  ;; normalize (KEY N) to (KEY . N), as org does
  (when (and (listp spec) (listp (cdr spec)) (null (cddr spec)))
    (setq spec (cons (car spec) (cadr spec))))
  (pcase spec
    (`t (cons 1 most-positive-fixnum))
    (`(:maxlevel . ,(and (pred integerp) n)) (cons 1 n))
    (`(:level . ,(and (pred integerp) n)) (cons n n))))

(defun vulpea-para-refile--file-targets (path notes levels)
  "Return the target-table entries for the file PATH.

NOTES are the notes living in PATH (any levels, any order); LEVELS is
a (MIN . MAX) cons bounding which heading levels become targets.
Outline paths are reconstructed from the notes' levels and positions,
and the target strings follow `org-refile-use-outline-path'."
  (let* ((style org-refile-use-outline-path)
         (file-note (seq-find (lambda (n) (= 0 (vulpea-note-level n))) notes))
         (base (pcase style
                 (`file (file-name-nondirectory path))
                 (`full-file-path path)
                 (`title (or (and file-note (vulpea-note-title file-note))
                             (file-name-nondirectory path)))
                 (`buffer-name (if-let* ((buf (find-buffer-visiting path)))
                                   (buffer-name buf)
                                 (file-name-nondirectory path)))
                 (_ nil)))
         (headings (sort (seq-filter (lambda (n) (> (vulpea-note-level n) 0))
                                     notes)
                         (lambda (a b) (< (vulpea-note-pos a)
                                          (vulpea-note-pos b)))))
         (stack nil)
         (targets nil))
    ;; the file itself is a target under the file-naming styles, just
    ;; like in `org-refile-get-targets'
    (when base
      (push (list base path nil nil) targets))
    (dolist (note headings)
      (let ((level (vulpea-note-level note)))
        (while (and stack (>= (caar stack) level))
          (pop stack))
        (push (cons level (vulpea-note-title note)) stack)
        (when (and (<= (car levels) level) (<= level (cdr levels)))
          (let ((olp (mapcar (lambda (s)
                               (replace-regexp-in-string "/" "\\/" s nil t))
                             (reverse (mapcar #'cdr stack)))))
            (push (list (if style
                            (mapconcat #'identity
                                       (if base (cons base olp) olp)
                                       "/")
                          (vulpea-note-title note))
                        path
                        ;; a loose position check: DB titles are
                        ;; normalized (links stripped), so org's exact
                        ;; heading regexp would reject valid targets;
                        ;; "still a heading here" catches stale
                        ;; positions all the same
                        org-outline-regexp
                        (vulpea-note-pos note))
                  targets)))))
    (nreverse targets)))

(defun vulpea-para-refile-target-table (&optional spec)
  "Build a refile target table from the database.

The result has the shape `org-refile-get-targets' produces, a list of
\(TARGET FILE REGEXP POSITION) entries: one entry per file (under the
file-naming `org-refile-use-outline-path' styles) plus one per heading
the database knows in it, grouped by file with area files first.  No
file is visited; positions and outline paths come straight from the
database, which also means the targets are the vault's *notes*: a
heading vulpea does not index is not offered.

SPEC is the SPECIFICATION part of an `org-refile-targets' entry and
must be level-based (see `vulpea-para-refile--spec-levels'); it
defaults to (:maxlevel . 3).

One query fetches every note; asking the database per file, or even
for the file subset, turned out an order of magnitude slower on a real
vault than filtering the full set here."
  (let ((levels (or (vulpea-para-refile--spec-levels (or spec '(:maxlevel . 3)))
                    (user-error "Unsupported refile spec: %S" spec)))
        ;; materializing thousands of notes churns the GC hard enough
        ;; to triple the build time; defer it for the duration
        (gc-cons-threshold most-positive-fixnum))
    (let ((notes (vulpea-db-query))
          (by-path (make-hash-table :test #'equal)))
      (dolist (note notes)
        (push note (gethash (vulpea-note-path note) by-path)))
      (mapcan (lambda (path)
                (vulpea-para-refile--file-targets
                 path (gethash path by-path) levels))
              (vulpea-para-refile--file-paths
               (seq-filter (lambda (n) (= 0 (vulpea-note-level n))) notes))))))

(defun vulpea-para-refile--get-targets (orig &rest args)
  "Answer `org-refile-get-targets' from the database when possible.

When `org-refile-targets' is a single `vulpea-para-refile-files' entry
with a level-based spec, return `vulpea-para-refile-target-table'
without touching a file.  Anything else, including the values org-goto
and friends let-bind, goes to ORIG (with ARGS) untouched."
  (let ((entry (and (null (cdr org-refile-targets))
                    (car-safe org-refile-targets))))
    (if (and (consp entry)
             (eq (car entry) 'vulpea-para-refile-files)
             (vulpea-para-refile--spec-levels (cdr entry)))
        (vulpea-para-refile-target-table (cdr entry))
      (apply orig args))))

;;;###autoload
(define-minor-mode vulpea-para-refile-mode
  "Answer refile targets from the database instead of scanning files.

Org builds its refile target table by visiting every candidate file,
which takes minutes across a whole vault.  With this mode on,
`org-refile-get-targets' is answered by a database query (see
`vulpea-para-refile-target-table') whenever `org-refile-targets' is
the vulpea-para spec, a single `vulpea-para-refile-files' entry; any
other value falls through to org's own scan, so org-goto and manual
restrictions keep working."
  :global t
  :group 'vulpea-para
  (if vulpea-para-refile-mode
      (advice-add 'org-refile-get-targets :around
                  #'vulpea-para-refile--get-targets)
    (advice-remove 'org-refile-get-targets
                   #'vulpea-para-refile--get-targets)))

(provide 'vulpea-para-refile)
;;; vulpea-para-refile.el ends here
