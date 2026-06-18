;;; vulpea-para.el --- PARA method on top of Vulpea -*- lexical-binding: t; -*-
;;
;; Copyright (c) 2024-2026 Boris Buliga <boris@d12frosted.io>
;;
;; Author: Boris Buliga <boris@d12frosted.io>
;; Maintainer: Boris Buliga <boris@d12frosted.io>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.2") (vulpea "2.2.0"))
;;
;; Created: 18 Jun 2026
;;
;; URL: https://github.com/d12frosted/vulpea-para
;;
;; License: GPLv3
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see
;; <http://www.gnu.org/licenses/>.
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; vulpea-para brings the PARA method (Projects, Areas, Resources,
;; Archives) to your notes without making you file anything into
;; folders.  Instead of moving notes around, it reads a note's role
;; from its tags and answers questions with fast database queries:
;; which areas do I have, what projects are active, what feeds this
;; project, what has gone quiet.
;;
;; It is built on vulpea (https://github.com/d12frosted/vulpea) and is
;; deliberately small.  The logic here used to live scattered across a
;; personal Emacs config; this is the same idea, made testable and
;; explained.
;;
;; This file is the umbrella; it just loads the pieces:
;;
;; - `vulpea-para-core'   - the tags and the bucket predicates.
;; - `vulpea-para-db'     - the database-backed read API (areas,
;;                          projects, resources, and how they relate).
;; - `vulpea-para-agenda'  - the self-updating agenda, its views and
;;                          command building blocks.
;; - `vulpea-para-capture' - capture areas, projects, tasks, and meetings.
;; - `vulpea-para-find'    - find areas, projects, and resources.
;; - `vulpea-para-archive' - archive finished projects.
;; - `vulpea-para-doctor'  - find and report inconsistencies.
;;
;; See the README and docs/ for the ideas and the guides.
;;
;;; Code:

(require 'vulpea-para-core)
(require 'vulpea-para-db)
(require 'vulpea-para-agenda)
(require 'vulpea-para-capture)
(require 'vulpea-para-archive)
(require 'vulpea-para-find)
(require 'vulpea-para-doctor)

(require 'org-agenda)
(require 'org-capture)

;;;###autoload
(defun vulpea-para-setup-defaults ()
  "Install opinionated vulpea-para defaults.

This is opt-in convenience.  It turns on `vulpea-para-agenda-mode' and
sets `org-agenda-custom-commands', `org-agenda-prefix-format', and
`org-capture-templates' from vulpea-para's building blocks, so you get a
working agenda and capture out of the box.

It overwrites `org-agenda-custom-commands' and
`org-agenda-prefix-format', and appends to `org-capture-templates'.
Skip it and wire things by hand if you want full control over the
layout (see the README)."
  (vulpea-para-agenda-mode 1)
  (setq org-agenda-custom-commands
        `((" " "PARA agenda"
           (,vulpea-para-agenda-cmd-refile
            ,vulpea-para-agenda-cmd-today
            ,vulpea-para-agenda-cmd-focus
            ,vulpea-para-agenda-cmd-stuck-projects
            ,vulpea-para-agenda-cmd-waiting
            ,(vulpea-para-agenda-cmd-current-quarter)))))
  (setq org-agenda-prefix-format
        '((agenda . " %(vulpea-para-agenda-category 36) %?-12t %12s")
          (todo   . " %(vulpea-para-agenda-category 36) ")
          (tags   . " %(vulpea-para-agenda-category 36) ")
          (search . " %(vulpea-para-agenda-category 36) ")))
  (setq org-capture-templates
        (append
         org-capture-templates
         `(("p" "PARA project" entry
            (function vulpea-para-capture-project-target)
            (function vulpea-para-capture-project-template))
           ("m" "PARA meeting" entry
            (function vulpea-para-capture-meeting-target)
            (function vulpea-para-capture-meeting-template))))))

(provide 'vulpea-para)
;;; vulpea-para.el ends here
