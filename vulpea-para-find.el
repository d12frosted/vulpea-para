;;; vulpea-para-find.el --- Find areas, projects, and resources -*- lexical-binding: t; -*-
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
;; Getting around.  Jump to an area, a project, or a resource with
;; completion.  These are thin commands over the read API and vulpea's
;; own selection and visiting, so there is nothing here you cannot do by
;; hand; they just save the typing.
;;
;;; Code:

(require 'vulpea)
(require 'vulpea-para-db)

;;;###autoload
(defun vulpea-para-find-area (&optional other-window)
  "Select an area and visit it.

With OTHER-WINDOW (a prefix argument), visit it in another window."
  (interactive "P")
  (vulpea-visit (vulpea-select-from "Area" (vulpea-para-areas)
                                    :require-match t)
                other-window))

;;;###autoload
(defun vulpea-para-find-project (&optional other-window)
  "Select a project and visit it.

With OTHER-WINDOW (a prefix argument), visit it in another window."
  (interactive "P")
  (vulpea-visit (vulpea-select-from "Project" (vulpea-para-projects)
                                    :require-match t)
                other-window))

;;;###autoload
(defun vulpea-para-find-resource (&optional other-window)
  "Select a resource and visit it.

With OTHER-WINDOW (a prefix argument), visit it in another window."
  (interactive "P")
  (vulpea-visit (vulpea-select-from "Resource" (vulpea-para-resources)
                                    :require-match t)
                other-window))

(provide 'vulpea-para-find)
;;; vulpea-para-find.el ends here
