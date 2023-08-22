;;; daric-mode.el --- Major mode for editing Daric code  -*- lexical-binding: t -*-

;; Copyright (C) 2017-2023 Krzysztof Kielak

;; Author: Krzysztof Kielak
;; Created: August 2023
;; Version: 0.1.0
;; Keywords: daric, basic, languages
;; URL: https://github.com/appblue/daric-mode.el
;; Package-Requires: ((seq "2.20") (emacs "25.1"))

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package is completely based on fantastic 'basic-mode' package
;; from Johan Dykstrom, available at
;; https://github.com/dykstrom/daric-mode. I have just adapted it for
;; Daric, but I'm going to move forward with the implementation of
;; Daric specific features.

;; This package provides a major mode for editing BASIC code.  Features
;; include syntax highlighting and indentation, as well as support for
;; auto-numbering and renumering of code lines.
;;
;; The base mode provides basic functionality and is normally only used
;; to derive sub modes for different BASIC dialects, see for example
;; `daric-generic-mode'.  For a list of available sub modes, please see
;; https://github.com/dykstrom/daric-mode, or the end of the source code
;; file.
;;
;; By default, daric-mode will open BASIC files in the generic sub mode.
;; To change this, you can use a file variable, or associate BASIC files
;; with another sub mode in `auto-mode-alist'.
;;
;; You can format the region, or the entire buffer, by typing C-c C-f.
;;
;; When line numbers are turned on, hitting the return key will insert
;; a new line starting with a fresh line number.  Typing C-c C-r will
;; renumber all lines in the region, or the entire buffer, including
;; any jumps in the code.
;;
;; Type M-. to lookup the line number, label, or variable at point,
;; and type M-, to go back again.  See also function
;; `xref-find-definitions'.

;; Installation:

;; The recommended way to install daric-mode is from MELPA, please see
;; https://melpa.org.
;;
;; To install manually, place daric-mode.el in your load-path, and add
;; the following lines of code to your init file:
;;
;; (autoload 'daric-generic-mode "daric-mode" "Major mode for editing Daric code." t)
;; (add-to-list 'auto-mode-alist '("\\.daric\\'" . daric-generic-mode))
;; (add-hook 'daric-mode-hook #'custom-daric-hook)
;; (add-hook 'daric-generic-mode-hook #'custom-daric-hook)
;; (defun custom-daric-hook ()
;;   (setq indent-tabs-mode nil)
;;   (message "Hello to Daric mode!"))


;; Configuration:

;; You can customize the indentation of code blocks, see variable
;; `daric-indent-offset'.  The default value is 4.
;;
;; Formatting is also affected by the customizable variables
;; `daric-delete-trailing-whitespace' and `delete-trailing-lines'
;; (from simple.el).
;;
;; You can also customize the number of columns to allocate for
;; line numbers using the variable `daric-line-number-cols'. The
;; default value of 0 (no space reserved), is appropriate for
;; programs with no line numbers and for left aligned numbering.
;; Use a positive integer, such as 6, if you prefer right alignment.
;;
;; The other line number features can be configured by customizing
;; the variables `daric-auto-number', `daric-renumber-increment' and
;; `daric-renumber-unnumbered-lines'.
;;
;; Whether syntax highlighting requires separators between keywords can be
;; customized with variable `daric-syntax-highlighting-require-separator'.

;;; Change Log:

;;  0.1.0  2023-08-22  Initial version.

;;; Code:

(require 'simple)
(require 'seq)

;; ----------------------------------------------------------------------------
;; Customization:
;; ----------------------------------------------------------------------------

(defgroup daric nil
  "Major mode for editing DARIC code."
  :link '(emacs-library-link :tag "Source File" "daric-mode.el")
  :group 'languages)

(defcustom daric-mode-hook nil
  "*Hook run when entering BASIC mode."
  :type 'hook
  :group 'daric)

(defcustom daric-indent-offset 4
  "*Specifies the indentation offset for `daric-indent-line'.
Statements inside a block are indented this number of columns."
  :type 'integer
  :group 'daric)

(defcustom daric-line-number-cols 0
  "*Specifies the number of columns to allocate to line numbers.
This number includes the single space between the line number and
the actual code. Leave this variable at 0 if you do not use line
numbers or if you prefer left aligned numbering. A positive value
adds sufficient padding to right align a line number and add a
space afterward. The value 6 is reasonable for older dialects of
BASIC which used at most five digits for line numbers."
  :type 'integer
  :group 'daric)

(defcustom daric-delete-trailing-whitespace t
  "*Delete trailing whitespace while formatting code."
  :type 'boolean
  :group 'daric)

(defcustom daric-auto-number nil
  "*Specifies auto-numbering increments.
If nil, auto-numbering is turned off.  If not nil, this should be an
integer defining the increment between line numbers, 10 is a traditional
choice."
  :type '(choice (const :tag "Off" nil)
         integer)
  :group 'daric)

(defcustom daric-renumber-increment 10
  "*Default auto-numbering increment."
  :type 'integer
  :group 'daric)

(defcustom daric-renumber-unnumbered-lines t
  "*If non-nil, lines without line numbers are also renumbered.
If nil, lines without line numbers are left alone.  Completely
empty lines are never numbered."
  :type 'boolean
  :group 'daric)

(defcustom daric-syntax-highlighting-require-separator t
  "*If non-nil, only keywords separated by symbols will be highlighted.
If nil, the default, keywords separated by numbers will also be highlighted."
  :type 'boolean
  :group 'daric)

;; ----------------------------------------------------------------------------
;; Variables:
;; ----------------------------------------------------------------------------

(defconst daric-mode-version "1.0.0"
  "The current version of `daric-mode'.")

(defvar-local daric-increase-indent-keywords-bol
  '("for" "def")
  "List of keywords that increase indentation.
These keywords increase indentation when found at the
beginning of a line.")
(defvar-local daric-increase-indent-keywords-bol-regexp nil)

(defvar-local daric-increase-indent-keywords-eol
  '("else" "then" "elseif")
  "List of keywords that increase indentation.
These keywords increase indentation when found at the
end of a line.")
(defvar-local daric-increase-indent-keywords-eol-regexp nil)

(defvar-local daric-decrease-indent-keywords-bol
  '("else" "end" "next" "enddef" "endif")
  "List of keywords that decrease indentation.
These keywords decrease indentation when found at the
beginning of a line or after a statement separator (:).")
(defvar-local daric-decrease-indent-keywords-bol-regexp nil)

(defvar-local daric-comment-and-string-faces
  '(font-lock-comment-face font-lock-comment-delimiter-face font-lock-string-face)
  "List of font-lock faces used for comments and strings.")

(defvar-local daric-comment-regexp
  "\\_<rem\\_>.*\n"
  "Regexp string that matches a comment until the end of the line.")

(defvar-local daric-linenum-regexp
  "^[ \t]*\\([0-9]+\\)"
  "Regexp string of symbols to highlight as line numbers.")

(defvar-local daric-label-regexp
  "^[ \t]*\\([a-zA-Z][a-zA-Z0-9_.]*:\\)"
  "Regexp string of symbols to highlight as labels.")

(defvar-local daric-constants
  nil
  "List of symbols to highlight as constants.")

(defvar-local daric-functions
  '("abs" "asc" "atn" "chr$" "cos" "exp" "int" "len" "log"
    "pi" "rnd" "sgn" "sin" "sqr" "str$" "tab" "tan" "val")
  "List of symbols to highlight as functions.")

(defvar-local daric-builtins
  '("and" "cls" "data" "input" "let" "mod" "not" "or"
    "peek" "poke" "print" "read" "restore" "xor")
  "List of symbols to highlight as builtins.")

(defvar-local daric-keywords
  '("def fn" "def" "dim" "else" "end" "enddef" "endif" "error" "exit"
    "for" "gosub" "go sub" "goto" "go to" "if" "next"
    "on" "step" "randomize" "return" "then" "to" "endif" "enddef")
  "List of symbols to highlight as keywords.")

(defvar-local daric-types
  nil
  "List of symbols to highlight as types.")

(defvar-local daric-font-lock-keywords
  nil
  "Describes how to syntax highlight keywords in `daric-mode' buffers.
This is initialized by `daric-mode-initialize' from lists that may be
modified in derived submodes.")

(defvar-local daric-font-lock-syntax
  '(("0123456789" . "."))
  "Syntax alist used to set the Font Lock syntax table.
This syntax table is used to highlight keywords adjacent to numbers,
e.g. GOTO10. See `daric-syntax-highlighting-require-separator'.")

;; ----------------------------------------------------------------------------
;; Indentation:
;; ----------------------------------------------------------------------------

(defun daric-indent-line ()
  "Indent the current line of code, see function `daric-calculate-indent'."
  (interactive)
  ;; If line needs indentation
  (when (or (not (daric-line-number-indented-correctly-p))
            (not (daric-code-indented-correctly-p)))
    ;; Set daric-line-number-cols to reflect the actual code
    (let* ((actual-line-number-cols
            (if (not (daric-has-line-number-p))
                0
              (let ((line-number (daric-current-line-number)))
                (1+ (length (number-to-string line-number))))))
           (daric-line-number-cols
            (max actual-line-number-cols daric-line-number-cols)))
      ;; Calculate new indentation
      (let* ((original-col (- (current-column) daric-line-number-cols))
             (original-indent-col (daric-current-indent))
             (calculated-indent-col (daric-calculate-indent)))
        (daric-indent-line-to calculated-indent-col)
        (move-to-column (+ calculated-indent-col
                           (max (- original-col original-indent-col) 0)
                           daric-line-number-cols))))))

(defun daric-calculate-indent ()
  "Calculate the indent for the current line of code.
The current line is indented like the previous line, unless inside a block.
Code inside a block is indented `daric-indent-offset' extra characters."
  (let ((previous-indent-col (daric-previous-indent))
        (increase-indent (daric-increase-indent-p))
        (decrease-indent (daric-decrease-indent-p))
        (label (daric-label-p)))
    (if label
        0
      (max 0 (+ previous-indent-col
                (if increase-indent daric-indent-offset 0)
                (if decrease-indent (- daric-indent-offset) 0))))))

(defun daric-label-p ()
  "Return non-nil if current line does start with a label."
  (save-excursion
    (goto-char (line-beginning-position))
    (looking-at daric-label-regexp)))

(defun daric-comment-or-string-p ()
  "Return non-nil if point is in a comment or string."
  (let ((faces (get-text-property (point) 'face)))
    (unless (listp faces)
      (setq faces (list faces)))
    (seq-some (lambda (x) (memq x faces)) daric-comment-and-string-faces)))

(defun daric-comment-p ()
  "Return non-nil if point is in a comment."
  (let ((comment-or-string (car (daric-comment-or-string-p))))
    (or (equal comment-or-string font-lock-comment-face)
        (equal comment-or-string font-lock-comment-delimiter-face))))

(defun daric-comment-lead ()
  "Return the comment lead of the comment at point.
If the point is not in a comment, return nil."
  (when (daric-comment-p)
    (save-excursion
      (while (and (not (bolp)) (daric-comment-p))
        (forward-char -1))
      (let ((case-fold-search t))
        (when (re-search-forward "'\\|rem" nil t)
          (match-string 0))))))

(defun daric-code-search-backward ()
  "Search backward from point for a line containing code."
  (beginning-of-line)
  (skip-chars-backward " \t\n")
  (while (and (not (bobp)) (or (daric-comment-or-string-p) (daric-label-p)))
    (skip-chars-backward " \t\n")
    (when (not (bobp))
      (forward-char -1))))

(defun daric-match-symbol-at-point-p (regexp)
  "Return non-nil if the symbol at point does match REGEXP."
  (let ((symbol (symbol-at-point))
        (case-fold-search t))
    (when symbol
      (string-match regexp (symbol-name symbol)))))

(defun daric-increase-indent-p ()
  "Return non-nil if indentation should be increased.
Some keywords trigger indentation when found at the end of a line,
while other keywords do it when found at the beginning of a line."
  (save-excursion
    (daric-code-search-backward)
    (unless (bobp)
      ;; Keywords at the end of the line
      (if (daric-match-symbol-at-point-p daric-increase-indent-keywords-eol-regexp)
          't
        ;; Keywords at the beginning of the line
        (beginning-of-line)
        (re-search-forward "[^0-9 \t\n]" (line-end-position) t)
        (daric-match-symbol-at-point-p daric-increase-indent-keywords-bol-regexp)))))

(defun daric-decrease-indent-p ()
  "Return non-nil if indentation should be decreased.
Some keywords trigger un-indentation when found at the beginning
of a line or statement, see `daric-decrease-indent-keywords-bol'."
  (save-excursion
    (beginning-of-line)
    (re-search-forward "[^0-9 \t\n]" (line-end-position) t)
    (or (daric-match-symbol-at-point-p daric-decrease-indent-keywords-bol-regexp)
        (let ((match nil))
          (daric-code-search-backward)
          (beginning-of-line)
          (while (and (not match)
                      (re-search-forward ":[ \t\n]*" (line-end-position) t))
            (setq match (daric-match-symbol-at-point-p daric-decrease-indent-keywords-bol-regexp)))
          match))))

(defun daric-current-indent ()
  "Return the indent column of the current code line.
The columns allocated to the line number are ignored."
  (save-excursion
    (beginning-of-line)
    ;; Skip line number and spaces
    (skip-chars-forward "0-9 \t" (line-end-position))
    (- (current-column) daric-line-number-cols)))

(defun daric-previous-indent ()
  "Return the indent column of the previous code line.
The columns allocated to the line number are ignored.
If the current line is the first line, then return 0."
  (save-excursion
    (daric-code-search-backward)
    (cond ((bobp) 0)
          (t (daric-current-indent)))))

(defun daric-line-number-indented-correctly-p ()
  "Return non-nil if line number is indented correctly.
If there is no line number, also return non-nil."
  (save-excursion
    (if (not (daric-has-line-number-p))
        t
      (beginning-of-line)
      (skip-chars-forward " \t" (line-end-position))
      (skip-chars-forward "0-9" (line-end-position))
      (and (looking-at "[ \t]")
           (= (point) (+ (line-beginning-position) daric-line-number-cols -1))))))

(defun daric-code-indented-correctly-p ()
  "Return non-nil if code is indented correctly."
  (save-excursion
    (let ((original-indent-col (daric-current-indent))
          (calculated-indent-col (daric-calculate-indent)))
      (= original-indent-col calculated-indent-col))))

(defun daric-has-line-number-p ()
  "Return non-nil if the current line has a line number."
  (save-excursion
    (beginning-of-line)
    (skip-chars-forward " \t" (line-end-position))
    (looking-at "[0-9]")))

(defun daric-remove-line-number ()
  "Remove and return the line number of the current line.
After calling this function, the current line will begin with the first
non-blank character after the line number."
  (if (not (daric-has-line-number-p))
      ""
    (beginning-of-line)
    (re-search-forward "\\([0-9]+\\)" (line-end-position) t)
    (let ((line-number (match-string-no-properties 1)))
      (delete-region (line-beginning-position) (match-end 1))
      line-number)))

(defun daric-format-line-number (number)
  "Format NUMBER as a line number."
  (if (= daric-line-number-cols 0)
      (format "%s" number)
    (format (concat "%" (number-to-string (- daric-line-number-cols 1)) "s ") number)))

(defun daric-indent-line-to (column)
  "Indent current line to COLUMN, also considering line numbers."
  ;; Remove line number
  (let* ((line-number (daric-remove-line-number))
         (formatted-number (daric-format-line-number line-number))
         (beg (point)))
    ;; Indent line
    (indent-line-to column)
    ;; Add line number again
    (unless (string= line-number "")
      (untabify beg (point)))
    (beginning-of-line)

    (insert formatted-number)))

(defun daric-electric-colon ()
  "Insert a colon and re-indent line."
  (interactive)
  (insert ?\:)
  (when (not (daric-comment-or-string-p))
    (daric-indent-line)))

;; ----------------------------------------------------------------------------
;; Formatting:
;; ----------------------------------------------------------------------------

(defun daric-delete-trailing-whitespace-line ()
  "Delete any trailing whitespace on the current line."
  (beginning-of-line)
  (when (re-search-forward "\\s-*$" (line-end-position) t)
    (replace-match "")))

(defun daric-format-code ()
  "Format all lines in region, or entire buffer if region is not active.
Indent lines, and also remove any trailing whitespace if the
variable `daric-delete-trailing-whitespace' is non-nil.

If this command acts on the entire buffer it also deletes all
trailing lines at the end of the buffer if the variable
`delete-trailing-lines' is non-nil."
  (interactive)
  (let* ((entire-buffer (not (use-region-p)))
         (point-start (if (use-region-p) (region-beginning) (point-min)))
         (point-end (if (use-region-p) (region-end) (point-max)))
         (line-end (line-number-at-pos point-end)))

    (save-excursion
      ;; Don't format last line if region ends on first column
      (goto-char point-end)
      (when (= (current-column) 0)
        (setq line-end (1- line-end)))

      ;; Loop over all lines and format
      (goto-char point-start)
      (while (and (<= (line-number-at-pos) line-end) (not (eobp)))
        (daric-indent-line)
        (when daric-delete-trailing-whitespace
          (daric-delete-trailing-whitespace-line))
        (forward-line))

      ;; Delete trailing empty lines
      (when (and entire-buffer
                 delete-trailing-lines
                 (= (point-max) (1+ (buffer-size)))) ;; Really end of buffer?
        (goto-char (point-max))
        (backward-char)
        (while (eq (char-before) ?\n)
          (delete-char -1))))))

;; ----------------------------------------------------------------------------
;; Line numbering:
;; ----------------------------------------------------------------------------

(defun daric-current-line-number ()
  "Return line number of current line, or nil if no line number."
  (save-excursion
    (when (daric-has-line-number-p)
      (beginning-of-line)
      (re-search-forward "\\([0-9]+\\)" (line-end-position) t)
      (let ((line-number (match-string-no-properties 1)))
        (string-to-number line-number)))))

(defun daric-looking-at-line-number-p (line-number)
  "Return non-nil if text after point matches LINE-NUMBER."
  (and line-number
       (looking-at (concat "[ \t]*" (int-to-string line-number)))
       (looking-back "^[ \t]*" nil)))

(defun daric-newline-and-number ()
  "Insert a newline and indent to the proper level.
If the current line starts with a line number, and auto-numbering is
turned on (see `daric-auto-number'), insert the next automatic number
in the beginning of the line.

If opening a new line between two numbered lines, and the next
automatic number would be >= the line number of the existing next
line, we try to find a midpoint between the two existing lines
and use that as the next number.  If no more unused line numbers
are available between the existing lines, just increment by one,
even if that creates overlaps."
  (interactive)
  (let* ((current-column (current-column))
         (current-line-number (daric-current-line-number))
         (before-line-number (daric-looking-at-line-number-p current-line-number))
         (next-line-number (save-excursion
                             (end-of-line)
                             (and (forward-word 1)
                                  (daric-current-line-number))))
         (new-line-number (and current-line-number
                               daric-auto-number
                               (+ current-line-number daric-auto-number)))
         (comment-lead (daric-comment-lead)))
    (daric-indent-line)
    (newline)
    (when (and next-line-number
               new-line-number
               (<= next-line-number new-line-number))
      (setq new-line-number
            (+ current-line-number
               (truncate (- next-line-number current-line-number) 2)))
      (when (= new-line-number current-line-number)
        (setq new-line-number (1+ new-line-number))))
    (unless before-line-number
      (if new-line-number
          (insert (concat (int-to-string new-line-number) " ")))
      (if (and comment-lead
               (not (eolp))
               (not (looking-at comment-lead)))
          (insert (concat comment-lead " "))))
    (daric-indent-line)
    ;; If the point was before the line number we want it to stay there
    (if before-line-number
        (move-to-column current-column))))

(defvar daric-jump-identifiers
  (regexp-opt '("edit" "else"
                "erl =" "erl <>" "erl >=" "erl <=" "erl >" "erl <"
                "gosub" "go sub" "goto" "go to"
                "list" "llist" "restore" "resume" "return" "run" "then"))
  "Regexp that matches identifiers that identifies jumps in the code.")

(defun daric-find-jumps ()
  "Find all jump targets and the jump statements that jump to them.
This returns a hash with line numbers for keys.  The value of each entry
is a list containing markers to each jump point (the number following a
GOTO, GOSUB, etc.) that jumps to this line number."
  (let* ((jump-targets (make-hash-table))
         (separator (if daric-syntax-highlighting-require-separator "[ \t]+" "[ \t]*"))
         (regexp (concat daric-jump-identifiers separator)))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward regexp nil t)
        (while (looking-at "\\([0-9]+\\)\\([ \t]*[,-][ \t]*\\)?")
          (let* ((target-string (match-string-no-properties 1))
                 (target (string-to-number target-string))
                 (jmp-marker (copy-marker (+ (point) (length target-string)))))
            (unless (gethash target jump-targets)
              (puthash target nil jump-targets))
            (push jmp-marker (gethash target jump-targets))
            (forward-char (length (match-string 0)))))))
    jump-targets))

(defun daric-renumber (start increment)
  "Renumbers the lines of the buffer or region.
The new numbers begin with START and use INCREMENT between
line numbers.

START defaults to the line number at the start of buffer or
region.  If no line number is present there, it uses
`daric-renumber-increment' as a fallback starting point.

INCREMENT defaults to `daric-renumber-increment'.

Jumps in the code are updated with the new line numbers.

If the region is active, only lines within the region are
renumbered, but jumps into the region are updated to match the
new numbers even if the jumps are from outside the region.

No attempt is made to ensure unique line numbers within the
buffer if only the active region is renumbered.

If `daric-renumber-unnumbered-lines' is non-nil, all non-empty
lines will get numbers.  If it is nil, only lines that already
have numbers are included in the renumbering."
  (interactive
   (list (let ((default (save-excursion
                          (goto-char (if (use-region-p)
                                         (region-beginning)
                                       (point-min)))
                          (or (daric-current-line-number)
                              daric-renumber-increment))))
           (string-to-number (read-string
                              (format "Renumber, starting with (default %d): " default)
                              nil nil
                              (int-to-string default))))
         (string-to-number (read-string
                            (format "Increment (default %d): " daric-renumber-increment)
                            nil nil
                            (int-to-string daric-renumber-increment)))))
  (let ((new-line-number start)
        (jump-list (daric-find-jumps))
        (point-start (if (use-region-p) (region-beginning) (point-min)))
        (point-end (if (use-region-p) (copy-marker (region-end)) (copy-marker (point-max)))))
    (save-excursion
      (goto-char point-start)
      (while (< (point) point-end)
        (unless (looking-at "^[ \t]*$")
          (let ((current-line-number (string-to-number (daric-remove-line-number))))
            (when (or daric-renumber-unnumbered-lines
                      (not (zerop current-line-number)))
              (let ((jump-locations (gethash current-line-number jump-list)))
                (save-excursion
                  (dolist (p jump-locations)
                    (goto-char (marker-position p))
                    (set-marker p nil)
                    (backward-kill-word 1)
                    (insert (int-to-string new-line-number)))))
              (beginning-of-line)
              (insert (daric-format-line-number new-line-number))
              (daric-indent-line)
              (setq new-line-number (+ new-line-number increment)))))
        (forward-line 1)))
    (set-marker point-end nil)
    (maphash (lambda (_target sources)
               (dolist (m sources)
                 (when (marker-position m)
                   (set-marker m nil))))
             jump-list)))

;; ----------------------------------------------------------------------------
;; Xref backend:
;; ----------------------------------------------------------------------------

(declare-function xref-make "xref" (summary location))
(declare-function xref-make-buffer-location "xref" (buffer point))

(defun daric-xref-backend ()
  "Return the xref backend used by `daric-mode'."
  'daric)

(defun daric-xref-make-xref (summary buffer point)
  "Return a buffer xref object with SUMMARY, BUFFER and POINT."
  (xref-make summary (xref-make-buffer-location buffer point)))

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql basic)))
  (daric-xref-identifier-at-point))

(defun daric-xref-identifier-at-point ()
  "Return the relevant BASIC identifier at point."
  (if daric-syntax-highlighting-require-separator
      (thing-at-point 'symbol t)
    (let ((number (thing-at-point 'number t))
          (symbol (thing-at-point 'symbol t)))
      (if number
          (number-to-string number)
        symbol))))

(cl-defmethod xref-backend-definitions ((_backend (eql basic)) identifier)
  (daric-xref-find-definitions identifier))

(defun daric-xref-find-definitions (identifier)
  "Find definitions of IDENTIFIER.
Return a list of xref objects with the definitions found.
If no definitions can be found, return nil."
  (let (xrefs)
    (let ((line-number (daric-xref-find-line-number identifier))
          (label (daric-xref-find-label identifier))
          (variables (daric-xref-find-variable identifier)))
      (when line-number
        (push (daric-xref-make-xref (format "%s (line number)" identifier) (current-buffer) line-number) xrefs))
      (when label
        (push (daric-xref-make-xref (format "%s (label)" identifier) (current-buffer) label) xrefs))
      (cl-loop for variable in variables do
            (push (daric-xref-make-xref (format "%s (variable)" identifier) (current-buffer) variable) xrefs))
      xrefs)))

(defun daric-xref-find-line-number (line-number)
  "Return the buffer position where LINE-NUMBER is defined.
If LINE-NUMBER is not found, return nil."
  (save-excursion
    (when (string-match "[0-9]+" line-number)
      (goto-char (point-min))
      (when (re-search-forward (concat "^\\s-*\\(" line-number "\\)\\s-") nil t)
        (match-beginning 1)))))

(defun daric-xref-find-label (label)
  "Return the buffer position where LABEL is defined.
If LABEL is not found, return nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward (concat "^\\s-*\\(" label "\\):") nil t)
      (match-beginning 1))))

(defun daric-xref-find-variable (variable)
  "Return a list of buffer positions where VARIABLE is defined.
If VARIABLE is not found, return nil."
  (save-excursion
    (goto-char (point-min))
    (let (positions)
      (while (re-search-forward (concat "\\_<dim\\_>.*\\_<\\(" variable "\\)\\_>") nil t)
        (push (match-beginning 1) positions))
      positions)))

;; ----------------------------------------------------------------------------
;; Word boundaries (based on subword-mode):
;; ----------------------------------------------------------------------------

(defconst daric-find-word-boundary-function-table
  (let ((tab (make-char-table nil)))
    (set-char-table-range tab t #'daric-find-word-boundary)
    tab)
  "Char table of functions to search for the word boundary.
Assigned to `find-word-boundary-function-table' when
`daric-syntax-highlighting-require-separator' is nil; defers to
`daric-find-word-boundary'.")

(defconst daric-empty-char-table
  (make-char-table nil)
  "Char table of functions to search for the word boundary.
Assigned to `find-word-boundary-function-table' when
custom word boundry functionality is not active.")

(defvar daric-forward-function 'daric-forward-internal
  "Function to call for forward movement.")

(defvar daric-backward-function 'daric-backward-internal
  "Function to call for backward movement.")

(defvar daric-alpha-regexp
  "[[:alpha:]$_.]+"
  "Regexp used by `daric-forward-internal' and `daric-backward-internal'.")

(defvar daric-not-alpha-regexp
  "[^[:alpha:]$_.]+"
  "Regexp used by `daric-forward-internal' and `daric-backward-internal'.")

(defvar daric-digit-regexp
  "[[:digit:]]+"
  "Regexp used by `daric-forward-internal' and `daric-backward-internal'.")

(defvar daric-not-digit-regexp
  "[^[:digit:]]+"
  "Regexp used by `daric-forward-internal' and `daric-backward-internal'.")

(defun daric-find-word-boundary (pos limit)
  "Catch-all handler in `daric-find-word-boundary-function-table'.
POS is the buffer position where to start the search.
LIMIT is used to limit the search."
  (let ((find-word-boundary-function-table daric-empty-char-table))
    (save-match-data
      (save-excursion
        (save-restriction
          (goto-char pos)
          (if (< pos limit)
              (progn
                (narrow-to-region (point-min) limit)
                (funcall daric-forward-function))
            (narrow-to-region limit (point-max))
            (funcall daric-backward-function))
          (point))))))

(defun daric-forward-internal ()
  "Default implementation of forward movement."
  (if (and (looking-at daric-alpha-regexp)
           (save-excursion
             (re-search-forward daric-alpha-regexp nil t))
           (> (match-end 0) (point)))
      (goto-char (match-end 0))
    (if (and (looking-at daric-digit-regexp)
             (save-excursion
               (re-search-forward daric-digit-regexp nil t))
             (> (match-end 0) (point)))
        (goto-char (match-end 0)))))


(defun daric-backward-internal ()
  "Default implementation of backward movement."
  (if (and (looking-at daric-alpha-regexp)
           (save-excursion
             (re-search-backward daric-not-alpha-regexp nil t)
             (re-search-forward daric-alpha-regexp nil t))
           (< (match-beginning 0) (point)))
      (goto-char (match-beginning 0))
    (if (and (looking-at daric-digit-regexp)
             (save-excursion
               (re-search-backward daric-not-digit-regexp nil t)
               (re-search-forward daric-digit-regexp nil t))
             (< (match-beginning 0) (point)))
        (goto-char (match-beginning 0)))))

;; ----------------------------------------------------------------------------
;; BASIC mode:
;; ----------------------------------------------------------------------------

(defvar-local daric-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-c\C-f" 'daric-format-code)
    (define-key map "\r" 'daric-newline-and-number)
    (define-key map "\C-c\C-r" 'daric-renumber)
    (define-key map ":" 'daric-electric-colon)
    map)
  "Keymap used in ‘daric-mode'.")

(defvar-local daric-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry (cons ?* ?/) ".   " table)   ; Operators * + , - . /
    (modify-syntax-entry (cons ?< ?>) ".   " table)   ; Operators < = >
    (modify-syntax-entry ?'           "<   " table)   ; Comment starts with '
    (modify-syntax-entry ?\n          ">   " table)   ; Comment ends with newline
    (modify-syntax-entry ?\^m         ">   " table)   ;                or carriage return
    table)
  "Syntax table used while in ‘daric-mode'.")

;;;###autoload
(define-derived-mode daric-mode prog-mode "Basic"
  "Major mode for editing BASIC code.

The base mode provides basic functionality and is normally
only used to derive sub modes for different BASIC dialects,
see for example `daric-generic-mode'.

Commands:

\\[indent-for-tab-command] indents for BASIC code.

\\[newline] can automatically insert a fresh line number if
`daric-auto-number' is set.  Default is disabled.

Customization:

You can customize the indentation of code blocks, see variable
`daric-indent-offset'.  The default value is 4.

Formatting is also affected by the customizable variables
`daric-delete-trailing-whitespace' and `delete-trailing-lines'
\(from simple.el).

You can also customize the number of columns to allocate for line
numbers using the variable `daric-line-number-cols'. The default
value of 0, no space reserved, is appropriate for programs with
no line numbers and for left aligned numbering. Use a larger
value if you prefer right aligned numbers. Note that the value
includes the space after the line number, so 6 right aligns
5-digit numbers.

The other line number features can be configured by customizing
the variables `daric-auto-number', `daric-renumber-increment' and
`daric-renumber-unnumbered-lines'.

Whether syntax highlighting requires separators between keywords
can be customized with variable
`daric-syntax-highlighting-require-separator'.

\\{daric-mode-map}"
  :group 'basic
  (add-hook 'xref-backend-functions #'daric-xref-backend nil t)
  (setq-local indent-line-function 'daric-indent-line)
  (setq-local comment-start "REM")
  (setq-local syntax-propertize-function
              (syntax-propertize-rules ("\\(\\_<REM\\_>\\)" (1 "<"))))
  (daric-mode-initialize))

(defun daric-mode-initialize ()
  "Initializations for sub-modes of `daric-mode'.
This is called by `daric-mode' on startup and by its derived modes
after making customizations to font-lock keywords and syntax tables."
  (setq-local daric-increase-indent-keywords-bol-regexp
          (regexp-opt daric-increase-indent-keywords-bol 'symbols))
  (setq-local daric-increase-indent-keywords-eol-regexp
          (regexp-opt daric-increase-indent-keywords-eol 'symbols))
  (setq-local daric-decrease-indent-keywords-bol-regexp
          (regexp-opt daric-decrease-indent-keywords-bol 'symbols))

  (let ((daric-constant-regexp (regexp-opt daric-constants 'symbols))
        (daric-function-regexp (regexp-opt daric-functions 'symbols))
        (daric-builtin-regexp (regexp-opt daric-builtins 'symbols))
        (daric-keyword-regexp (regexp-opt daric-keywords 'symbols))
        (daric-type-regexp (regexp-opt daric-types 'symbols)))
    (setq-local daric-font-lock-keywords
                (list (list daric-comment-regexp 0 'font-lock-comment-face)
                      (list daric-linenum-regexp 0 'font-lock-constant-face)
                      (list 'daric-find-linenum-ref 2 'font-lock-constant-face)
                      (list 'daric-find-linenum-ref-goto 2 'font-lock-constant-face)
                      (list 'daric-find-linenum-ref-delete 2 'font-lock-constant-face)
                      (list 'daric-find-linenum-ref-renum 1 'font-lock-constant-face)
                      (list daric-label-regexp 0 'font-lock-constant-face)
                      (list daric-constant-regexp 0 'font-lock-constant-face)
                      (list daric-keyword-regexp 0 'font-lock-keyword-face)
                      (list daric-type-regexp 0 'font-lock-type-face)
                      (list daric-function-regexp 0 'font-lock-function-name-face)
                      (list daric-builtin-regexp 0 'font-lock-builtin-face))))

  (if daric-syntax-highlighting-require-separator
      (progn
        (setq-local font-lock-defaults (list daric-font-lock-keywords nil t))
        (setq-local find-word-boundary-function-table daric-empty-char-table))
    (setq-local font-lock-defaults (list daric-font-lock-keywords nil t daric-font-lock-syntax))
    (setq-local find-word-boundary-function-table daric-find-word-boundary-function-table))
  (unless font-lock-mode
    (font-lock-mode 1)))

(defun daric-find-linenum-ref (bound)
  "Search forward from point to BOUND for line number references.
Set point to the end of the occurrence found, and return point.
This function handles the base case using a single regexp."
  (let* ((s (if daric-syntax-highlighting-require-separator "\s+" "\s*"))
         (regexp (concat "\\(edit" s
                         "\\|else" s
                         "\\|erl\s*=\s*"
                         "\\|erl\s*<>\s*"
                         "\\|erl\s*<\s*"
                         "\\|erl\s*>\s*"
                         "\\|erl\s*<=\s*"
                         "\\|erl\s*>=\s*"
                         "\\|restore" s
                         "\\|resume" s
                         "\\|return" s
                         "\\|run" s
                         "\\|then" s
                         "\\)"
                         "\\([0-9]+\\)")))
    (re-search-forward regexp bound t)))

(defun daric-find-linenum-ref-goto (bound)
  "Search forward from point to BOUND for GOTO/GOSUB line number references.
Set point to the end of the occurrence found, and return point.
This function finds line number references after GOTO/GOSUB and
ON x GOTO/GOSUB."
  (let* ((s (if daric-syntax-highlighting-require-separator "\s+" "\s*"))
         (bwd-regexp "go\s*\\(to\\|sub\\)[\s,0-9]+")
         (fwd-regexp "\\([\s,]*\\)\\([0-9]+\\)")
         (nxt-regexp (concat "go\s*\\(to\\|sub\\)" s "\\([0-9]+\\)")))
    (if (and (looking-back bwd-regexp (line-beginning-position)) (looking-at fwd-regexp))
        ;; If the previous keyword was GOTO/GOSUB followed by a line number, and we
        ;; are looking at another line number, this is an ON x GOTO/GOSUB statement
        (goto-char (match-end 2))
      ;; Otherwise, look for the next GOTO/GOSUB followed by a line number
      (re-search-forward nxt-regexp bound t))))

(defun daric-find-linenum-ref-delete (bound)
  "Search forward from point to BOUND for DELETE/LIST line number references.
Set point to the end of the occurrence found, and return point."
  (let* ((s (if daric-syntax-highlighting-require-separator "\s+" "\s*"))
         (bwd-regexp "\\(delete\\|ll?ist\\)[-\s0-9]+")
         (fwd-regexp "\\([-\s]*\\)\\([0-9]+\\)")
         (nxt-regexp (concat "\\(delete\\|ll?ist\\)" s "[-\s]*\\([0-9]+\\)")))
    (if (and (looking-back bwd-regexp (line-beginning-position)) (looking-at fwd-regexp))
        ;; If the previous keyword was DELETE/LIST followed by a line number,
        ;; and we are looking at another line number
        (goto-char (match-end 2))
      ;; Otherwise, look for the next DELETE/LIST followed by a line number
      (re-search-forward nxt-regexp bound t))))

(defun daric-find-linenum-ref-renum (bound)
  "Search forward from point to BOUND for RENUM line number references.
Set point to the end of the occurrence found, and return point."
  (let* ((s (if daric-syntax-highlighting-require-separator "\s+" "\s*"))
         (bwd-regexp "renum[\s0-9]+")
         (fwd-regexp "[\s,]*\\([0-9]+\\)")
         (nxt-regexp (concat "renum" s "[\s,]*\\([0-9]+\\)")))
    (if (and (looking-back bwd-regexp (line-beginning-position)) (looking-at fwd-regexp))
        ;; If the previous keyword was RENUM followed by a line number,
        ;; and we are looking at another line number
        (goto-char (match-end 1))
      ;; Otherwise, look for the next RENUM followed by a line number
      (re-search-forward nxt-regexp bound t))))

;; ----------------------------------------------------------------------------
;; Derived modes:
;; ----------------------------------------------------------------------------

;;;###autoload (add-to-list 'auto-mode-alist '("\\.daric\\'" . daric-generic-mode))

;;;###autoload
(define-derived-mode daric-generic-mode daric-qb45-mode "Daric[Generic]"
  "Generic BASIC programming mode.
This is the default mode that will be used if no sub mode is specified.
Derived from `daric-qb45-mode'.  For more information, see `daric-mode'."
  (daric-mode-initialize))

;;;###autoload
(define-derived-mode daric-qb45-mode daric-mode "Basic[QB 4.5]"
  "Programming mode for Microsoft QuickBasic 4.5.
Derived from `daric-mode'."

  ;; Notes:

  ;; * DATE$, MID$, PEN, PLAY, SCREEN, SEEK, STRIG, TIMER, and TIME$
  ;;   are both functions and statements, and are only highlighted as
  ;;   one or the other.

  ;; * $DYNAMIC, $INCLUDE, and $STATIC meta commands are not highlighted
  ;;   because they must appear in a comment.

  ;; * LOCAL, and SIGNAL are reserved for future use.

  ;; * The 'FOR' in 'OPEN "FILE" FOR OUTPUT AS #1' is highlighted the
  ;;   same as in FOR loop (a keyword). Should it be?

  (setq daric-functions
        '("abs" "and" "asc" "atn" "cdbl" "chr$" "cint" "clng" "command$"
          "cos" "csng" "csrlin" "cvd" "cvdmbf" "cvi" "cvl" "cvs" "cvsmbf"
          "date$" "environ$" "eof" "eqv" "erdev" "erdev$" "erl" "err"
          "exp" "fileattr" "fix" "fre" "freefile" "hex$" "imp" "inkey$"
          "inp" "input$" "instr" "int" "ioctl$" "lbound" "lcase$" "left$"
          "len" "loc" "lof" "log" "lpos" "ltrim$" "mid$" "mkd$" "mkdmbf$"
          "mki$" "mkl$" "mks$" "mksmbf$" "mod" "not" "oct$" "or" "pmap"
          "point" "pos" "right$" "rnd" "rtrim$" "sadd" "setmem" "sgn"
          "sin" "space$" "spc" "sqr" "stick" "str$" "string$" "tab" "tan"
          "time$" "ubound" "ucase$" "val" "varptr" "varptr$" "varseg"
          "xor"))

  (setq daric-builtins
        '("absolute" "access" "alias" "append" "beep" "binary" "bload"
          "bsave" "byval" "cdecl" "chdir" "circle" "clear" "close"
          "cls" "color" "com" "const" "data" "draw" "environ" "erase"
          "error" "field" "files" "get" "input" "input #" "ioctl"
          "interrupt" "key" "kill" "let" "line" "list" "locate" "lock"
          "lprint" "lset" "mkdir" "name" "open" "out" "output" "paint"
          "palette" "pcopy" "peek" "pen" "play" "poke" "preset" "print"
          "print #" "pset" "put" "random" "randomize" "read" "reset"
          "restore" "rmdir" "rset" "run" "screen" "seek" "shared" "sound"
          "static" "strig" "swap" "timer" "uevent" "unlock" "using" "view"
          "wait" "width" "window" "write" "write #"))

  (setq daric-keywords
        '("as" "call" "calls" "case" "chain" "common" "declare" "def"
          "def seg" "defdbl" "defint" "deflng" "defsng" "defstr" "dim"
          "do" "else" "elseif" "end" "endif" "exit" "for" "fn" "function"
          "gosub" "goto" "if" "is" "loop" "next" "off" "on" "on com"
          "on error" "on key" "on pen" "on play" "on strig" "on timer"
          "on uevent" "option base" "redim" "resume" "return" "select"
          "shell" "sleep" "step" "stop" "sub" "system" "then" "to"
          "type" "until" "wend" "while" "enddef" "endif"))

  (setq daric-types
        '("any" "double" "integer" "long" "single" "string"))

  (setq daric-increase-indent-keywords-bol
        '("case" "do" "for" "function" "repeat" "sub" "select" "while" "def"))
  (setq daric-increase-indent-keywords-eol
        '("else" "then"))
  (setq daric-decrease-indent-keywords-bol
        '("case" "else" "end" "loop" "next" "until" "wend" "endif" "enddef"))

  ;; Shorter than "REM"
  (setq-local comment-start "'")

  ;; Treat . and # as part of identifier ("input #" etc)
  (modify-syntax-entry ?. "w   " daric-mode-syntax-table)
  (modify-syntax-entry ?# "w   " daric-mode-syntax-table)

  (indent-tabs-mode)
  
  (daric-mode-initialize))

;; ----------------------------------------------------------------------------

(provide 'daric-mode)

;;; daric-mode.el ends here
