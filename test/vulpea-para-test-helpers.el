;;; vulpea-para-test-helpers.el --- Test helpers for vulpea-para -*- lexical-binding: t; -*-
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
;; Helpers for the database-backed tests: a throwaway vulpea database,
;; and a way to drop notes straight into it without touching any files.
;;
;;; Code:

(require 'org)
(require 'vulpea-db)

(defmacro vulpea-para-test--with-temp-db (&rest body)
  "Run BODY against a fresh, empty vulpea database.

Binds `vulpea-db-location' to a throwaway file and cleans it up
afterwards, even on error."
  (declare (indent 0))
  `(let* ((temp-file (make-temp-file "vulpea-para-test-" nil ".db"))
          (vulpea-db-location temp-file)
          (vulpea-db--connection nil))
     (unwind-protect
         (progn
           (vulpea-db)
           ,@body)
       (when vulpea-db--connection
         (vulpea-db-close))
       (when (file-exists-p temp-file)
         (delete-file temp-file)))))

(defun vulpea-para-test--insert (id title &rest args)
  "Insert a note (ID, TITLE, plus ARGS) straight into the database.

ARGS is a plist accepting :path, :level, :pos, :tags, :aliases, :meta,
:links, :properties, :todo, :priority, :file-title, and :modified-at.
No files are touched, which is what makes the query tests fast."
  (let ((level (or (plist-get args :level) 0)))
    (vulpea-db--insert-note
     :id id
     :path (or (plist-get args :path) (format "/tmp/%s.org" id))
     :level level
     :pos (or (plist-get args :pos) 0)
     :title title
     :tags (plist-get args :tags)
     :aliases (plist-get args :aliases)
     :meta (plist-get args :meta)
     :links (plist-get args :links)
     :properties (plist-get args :properties)
     :todo (plist-get args :todo)
     :priority (plist-get args :priority)
     :file-title (or (plist-get args :file-title)
                     (when (= level 0) title))
     :modified-at (or (plist-get args :modified-at) "2025-11-16 10:00:00"))))

(provide 'vulpea-para-test-helpers)
;;; vulpea-para-test-helpers.el ends here
