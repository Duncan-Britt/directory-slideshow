;;; directory-slideshow.el --- Simple slideshows from files -*- lexical-binding: t -*-

;; Author: Duncan Britt
;; Contact: https://github.com/Duncan-Britt/directory-slideshow/issues
;; URL: https://github.com/Duncan-Britt/directory-slideshow
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.4"))
;; Keywords: multimedia
;; URL: https://github.com/Duncan-Britt/directory-slideshow

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; ┌─────────┐
;; │ Summary │
;; └─────────┘
;; The premise of this package is that if you have a folder, you have
;; a slideshow. The files are the slides. You can create slideshows by
;; putting files (or symlinks) in folders. But you can also present
;; the contents of some arbitrary directory created for some other
;; purpose.

;; The slides themselves are completely ordinary buffers with no
;; additional settings associated with the slideshow.  Slide
;; transitions and are performed from a separate control frame,
;; inspired by Ediff. Further, the package imposes no restrictions on
;; which file types may be used as slides. This makes slides
;; interactive—you can highlight, edit, navigate, execute code,
;; find-file, split-window, etc., all without inhibitions. Moreover,
;; you can present the files you already have with no additional
;; setup, such as, for example, a photo album.

;; ┌──────────┐
;; │ Features │
;; └──────────┘
;; - Speaker notes via 'file-name.ext.speaker-notes'
;; - Upcoming slide previews in control frame
;; - Chunk (split window, 2 files per slide)
;; - Sliding Window (split window, sliding window effect)
;; - Autoplay slides
;; - Wrap around to beginning of slides
;; - With Dired-Narrow, can present a subset of files.
;; - Styles can be applied using `directory-slideshow-after-slide-render-hook'.

;; ┌──────────────┐
;; │ Installation │
;; └──────────────┘
;; Example Elpaca + use-package installation with custom keymap
;;
;;  (use-package directory-slideshow
;;    :ensure (:host github :repo "Duncan-Britt/directory-slideshow")
;;    :custom
;;    ((directory-slideshow-include-directories? t)
;;     (directory-slideshow-use-default-bindings nil))
;;    :bind
;;    (:map directory-slideshow-mode-map
;;          ("j" . directory-slideshow-advance)
;;          ("k" . directory-slideshow-retreat)
;;          ("l" . directory-slideshow-toggle-play)
;;          ("q" . directory-slideshow-quit)
;;          ("p" . directory-slideshow-toggle-preview-next-slide)
;;          ("w" . directory-slideshow-toggle-wrap-around)
;;          ("d" . directory-slideshow-toggle-autoplay-direction)
;;          ("t" . directory-slideshow-set-autoplay-timer)
;;          ("m" . directory-slideshow-set-presentation-mode)
;;          ("i" . directory-slideshow-toggle-landscape-images)))

;; ┌───────┐
;; │ Usage │
;; └───────┘
;; The command `directory-slideshow-start' will either prompt you for
;; a directory, or, if in Dired, will initialize a slideshow with the
;; files ins the current buffer.  Then all the relevant keybindings
;; for navigation and settings will be visible within the control
;; frame.

;; `directory-slideshow-after-slide-render-hook' provides a means by
;; which you can customize the appearance of slides. For example,
;;
;;  (defun my/slideshow-text-adjustment ()
;;    (when (derived-mode-p 'text-mode)
;;      (text-scale-set 2)
;;      (olivetti-mode 1)
;;      (olivetti-set-width 60)))
;;
;;  (add-hook 'directory-slideshow-after-slide-render-hook
;;            #'my/slideshow-text-adjustment)
;;

;; By default, slides are ordered lexicographically by file
;; name. `directory-slideshow-file-name-sort-compare-fn' can be set to
;; a custom function to change the way the slides are ordered.

;; To make any settings local to a slideshow, use '.dir-locals'.

;;; Code:
(require 'image-mode)
(require 'dired)

(defgroup directory-slideshow nil            ;; ┌──────────────────┐
  "Display directory contents as slideshow." ;; │ Custom Variables │
  :group 'convenience)                       ;; └──────────────────┘

(defcustom directory-slideshow-use-default-bindings t
  "Whether to use the default keybindings for directory-slideshow mode."
  :type 'boolean
  :group 'directory-slideshow)

(defcustom directory-slideshow-ignore-regexp "^\\."
  "Regular expression used to filter matching files from slideshow.
Default value ignores hidden files."
  :type '(choice (const :tag "None" nil)
                 (regexp :tag "Regular Expression"))
  :group 'directory-slideshow)

(defcustom directory-slideshow-include-directories? nil
  "When non-NIL, include open Dired buffers of subdirectories in slideshow."
  :type 'boolean
  :group 'directory-slideshow)

(defcustom directory-slideshow-wrap-around? t
  "When non-NIL, slideshow will wrap around when reaching the first or last slide."
  :type 'boolean
  :group 'directory-slideshow)

(defcustom directory-slideshow-preview-next-slide? t
  "When non-NIL, preview next slide in control buffer."
  :type 'boolean
  :group 'directory-slideshow)

(defcustom directory-slideshow-speaker-notes-suffix ".speaker-notes"
  "Suffix for speaker notes files.
When visiting a slide f, will look for speaker notes in f +
`directory-slideshow-speaker-notes-suffix'."
  :type 'string
  :group 'directory-slideshow)

(defcustom directory-slideshow-presentation-mode 'one-slide-at-a-time
  "Control how slides are displayed in directory slideshow.

The following modes are available:

\\='one-slide-at-a-time
  - Show only the current slide, one at a time
\\='chunk-two
  - Display slides in chunks of two.
\\='sliding-window
  - Show current slide on the right with the previous slide
    visible on the left."
  :type '(choice
          (const :tag "One slide at a time" one-slide-at-a-time)
          (const :tag "Chunk 2" chunk-two)
          (const :tag "Sliding Window" sliding-window))
  :group 'directory-slideshow)

(defcustom directory-slideshow-autoplay-interval 2.0
  "Determines whether to automatically advance the slideshow."
  :type 'float
  :group 'directory-slideshow)

(defcustom directory-slideshow-atomic-landscape-images? nil
  "Disallow split presentation frame for landscape images when non-NIL.
Only relevant when using \\='sliding-window option for
`directory-slideshow-presentation-mode'."
  :type 'boolean
  :group 'directory-slideshow)

(defcustom directory-slideshow-presentation-frame-alist
  '((name . "Slide show")
    (vertical-scroll-bars . nil)
    (horizontal-scroll-bars . nil))
  "Frame parameters for presentation frames in directory slideshow.
See `frame-parameters' for possible options."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'directory-slideshow)

(defcustom directory-slideshow-after-slide-render-hook nil
  "Hook run after a slide is rendered in the presentation frame.
Functions in this hook are called with no arguments when the
current slide has been rendered.  Use this to customize the
appearance of slides."
  :type 'hook
  :group 'directory-slideshow)

(defcustom directory-slideshow-file-name-sort-compare-fn #'string<
  "Function used to sort filenames in directory slideshow.
This should be a comparison function that takes two strings and
returns non-nil if the first string should sort before the
second."
  :type '(choice (const :tag "Lexicographic" string<)
                 (function :tag "Custom function"))
  :group 'directory-slideshow)

;; ┌──────────────────────────────────┐
;; │ Slideshow Buffer-Local Variables │
;; └──────────────────────────────────┘
(defvar-local directory-slideshow--presentation-frame nil
  "The presentation frame controlled by the control buffer.")

(defvar-local directory-slideshow--preview-windows nil
  "The windows of the preview of the next slide.")

(defvar-local directory-slideshow--slides nil
  "List of filenames associated with the current presentation.")

(defvar-local directory-slideshow--current-index 0
  "0-indexed slide number.")

(defvar-local directory-slideshow--speaker-notes nil
  "Speaker notes for current slide.")

(defvar-local directory-slideshow--autoplay-reverse? nil
  "When non-NIL, play slideshow in reverse when autoplaying.")

(defvar-local directory-slideshow--autoplay-timer nil
  "Timer for automatic slide advancement.")

;; ┌──────────┐
;; │ Commands │
;; └──────────┘
(defun directory-slideshow-toggle-preview-next-slide ()
  "Toggle the value of `directory-slideshow-preview-next-slide?' in buffer."
  (interactive)
  (setq-local directory-slideshow-preview-next-slide?
              (not directory-slideshow-preview-next-slide?))
  (directory-slideshow--render-preview)
  (directory-slideshow--render-control-buffer))

(defun directory-slideshow-toggle-autoplay-direction ()
    "Toggle between in-order and reverse-order for autoplay.
See `directory-slideshow--autoplay-reverse?'"
  (interactive)
  (setq-local directory-slideshow--autoplay-reverse?
              (not directory-slideshow--autoplay-reverse?))
  (directory-slideshow--render-control-buffer))

(defun directory-slideshow-toggle-play ()
  "Play or pause the slideshow."
  (interactive)
  (if directory-slideshow--autoplay-timer
      (progn
        (cancel-timer directory-slideshow--autoplay-timer)
        (setq-local directory-slideshow--autoplay-timer nil)
        (message "Slideshow autoplay stopped"))
    (let ((control-buffer (current-buffer))
          (control-frame (selected-frame)))
      (setq-local directory-slideshow--autoplay-timer
                  (run-with-timer
                   directory-slideshow-autoplay-interval
                   directory-slideshow-autoplay-interval
                   (lambda ()
                     (with-selected-frame control-frame
                       (with-current-buffer control-buffer
                         (unless (active-minibuffer-window)
                           (if directory-slideshow--autoplay-reverse?
                               (directory-slideshow-retreat)
                             (directory-slideshow-advance))))))))
      (message "Slideshow autoplay started")))
  (directory-slideshow--render-control-buffer))

(defun directory-slideshow-toggle-wrap-around ()
  "Toggle the value of `directory-slideshow-wrap-around?' in buffer."
  (interactive)
  (setq-local directory-slideshow-wrap-around?
              (not directory-slideshow-wrap-around?))
  (directory-slideshow--render-control-buffer)
  (directory-slideshow--render-preview))

(defun directory-slideshow-set-autoplay-timer ()
  "Set the time interval for autplay.
Update value of `directory-slideshow-autoplay-interval' and
restart `directory-slideshow--autoplay-timer' (if it exists)"
  (interactive)
  (let ((interval (read-number "New interval: " directory-slideshow-autoplay-interval)))
    (setq-local directory-slideshow-autoplay-interval
                interval)
    (when directory-slideshow--autoplay-timer
      (cancel-timer directory-slideshow--autoplay-timer)
      (let ((control-buffer (current-buffer))
            (control-frame (selected-frame)))
        (setq-local directory-slideshow--autoplay-timer
                    (run-with-timer
                     directory-slideshow-autoplay-interval
                     directory-slideshow-autoplay-interval
                     (lambda ()
                       (with-selected-frame control-frame
                         (with-current-buffer control-buffer
                           (unless (active-minibuffer-window)
                             (if directory-slideshow--autoplay-reverse?
                                 (directory-slideshow-retreat)
                               (directory-slideshow-advance))))))))
        (message "Slideshow autoplay started")))))

(defun directory-slideshow-set-presentation-mode ()
  "Update buffer-local value of `directory-slideshow-presentation-mode'."
  (interactive)
  (let* ((options '(("One slide at a time" . one-slide-at-a-time)
                    ("Chunk 2" . chunk-two)
                    ("Sliding Window" . sliding-window)))
         (choice (completing-read "Choose presentation mode: "
                                  (mapcar #'car options)
                                  nil t)))
    (setq-local directory-slideshow-presentation-mode
          (cdr (assoc choice options)))
    (directory-slideshow--render-control-buffer)))

(defun directory-slideshow-toggle-landscape-images ()
  "Toggle non-splitting of landscape images.
Update buffer-local value of
`directory-slideshow-atomic-landscape-images?'.  Relevant for
\\='sliding-window mode."
  (interactive)
  (setq-local directory-slideshow-atomic-landscape-images?
              (not directory-slideshow-atomic-landscape-images?))
  (directory-slideshow--render-control-buffer))

(defun directory-slideshow-make-speaker-notes ()
  "Create speaker-notes file for the current buffer-file."
  (interactive)
  (if-let (fname (buffer-file-name))
      (find-file (concat fname directory-slideshow-speaker-notes-suffix))
    (user-error "Attempt to make speaker-notes for a buffer with no file.")))

(defun directory-slideshow-quit ()
  "End the slideshow and cleanup."
  (interactive)
  (if (eq major-mode 'directory-slideshow-mode)
      (progn
        (directory-slideshow--cleanup)
        (kill-buffer))
    (user-error "Attempt to quit directory slideshow while not in `directory-slideshow-mode'.")))

(defun directory-slideshow-advance ()
  "Advance to the next slide."
  (interactive)
  (directory-slideshow--slide-index-advance)
  (directory-slideshow--go-to-current-slide)
  (directory-slideshow--render-preview))

(defun directory-slideshow-retreat ()
  "Revert to previous slide."
  (interactive)
  (directory-slideshow--slide-index-retreat)
  (directory-slideshow--go-to-current-slide)
  (directory-slideshow--render-preview))

;;;###autoload
(defun directory-slideshow-start (&optional directory)
  "Start the slideshow.
When called interactively, prompt for a DIRECTORY unless in Dired
mode."
  (interactive
   (list
    (if (eq major-mode 'dired-mode)
        dired-directory
      (read-directory-name "Select directory" default-directory))))

  (let* ((control-buffer-name (directory-slideshow--unique-buffer-name))
         (control-buffer (get-buffer-create control-buffer-name))
         (slides (directory-slideshow--get-slides directory)))
    (if slides
        (progn
          (switch-to-buffer control-buffer)
          (directory-slideshow-mode)
          (setq-local default-directory directory)
          (setq-local directory-slideshow--slides slides)
          (setq-local directory-slideshow--current-index 0)
          (setq header-line-format
                (substitute-command-keys
                 "Advance: \\[directory-slideshow-advance] Retreat: \\[directory-slideshow-retreat] Quit: \\[directory-slideshow-quit]"))
          (directory-slideshow--render-control-buffer)
          (directory-slideshow--render-preview)
          (add-hook 'kill-buffer-hook #'directory-slideshow--cleanup nil t)
          ;; NOTE: this action makes the presentation frame selected
          (setq-local directory-slideshow--presentation-frame (directory-slideshow--make-presentation-frame))
          (directory-slideshow--go-to-current-slide))
      (user-error "No slides in %s matching %s"
                  directory
                  directory-slideshow-ignore-regexp))))

;; ┌─────────────┐
;; │ Subroutines │
;; └─────────────┘

(defun directory-slideshow--make-presentation-frame ()
  "Return a new frame for presentations."
  (make-frame directory-slideshow-presentation-frame-alist))

(defun directory-slideshow--render-preview ()
  "Render preview of upcoming slides."
  (if directory-slideshow-preview-next-slide?
      (progn
        (directory-slideshow--cleanup-preview-window)
        (directory-slideshow--init-preview-window))
    (directory-slideshow--cleanup-preview-window)))

(defun directory-slideshow--cleanup-preview-window ()
  "Remove the preview window."
  (save-selected-window
    (dolist (win directory-slideshow--preview-windows)
      (when (window-live-p win)
        (delete-window win))))
  (setq-local directory-slideshow--preview-windows nil))

(defun directory-slideshow--init-preview-window ()
  "Make the preview window below the control window."
  (let (preview-win1 preview-win2)
    (save-selected-window
      ;; NOTE have to save preview-buffer before because
      ;; directory-slideshow--get-preview-buffer relies on values
      ;; local to the control buffer
      (setq preview-win1 (split-window (selected-window) nil 'below))
      (setq preview-win2 (cl-multiple-value-bind (preview-buffer-1 preview-buffer-2) (directory-slideshow--get-preview-buffer)
                           (select-window preview-win1)
                           (switch-to-buffer preview-buffer-1)
                           (when preview-buffer-2
                             (select-window (split-window-right))
                             (switch-to-buffer preview-buffer-2)
                             (selected-window)))))
    (setq-local directory-slideshow--preview-windows
                (if preview-win2
                    (list preview-win1 preview-win2)
                  (list preview-win1)))))

(defun directory-slideshow--get-slides (dir)
  "Get list of file names to include in slideshow from DIR.
If called from a narrowed Dired buffer, only include the visible files."
  (let ((slides (if (and (eq major-mode 'dired-mode)
                         (boundp 'dired-narrow-mode) ;; Check if dired-narrow is active
                         dired-narrow-mode)
                    ;; Get files from the narrowed Dired buffer
                    (let ((files nil))
                      (save-excursion
                        (goto-char (point-min))
                        (while (not (eobp))
                          (when-let* ((file (dired-get-filename nil t))
                                      (not-speaker-notes (not (string-match-p
                                                               (concat (regexp-quote directory-slideshow-speaker-notes-suffix) "$")
                                                               file)))
                                      (not-hidden (or (not directory-slideshow-ignore-regexp)
                                                      (not (string-match-p directory-slideshow-ignore-regexp
                                                                           (file-name-nondirectory file)))))
                                      (include-dir (or directory-slideshow-include-directories?
                                                       (not (file-directory-p file)))))
                            (push file files))
                          (forward-line 1)))
                      files)
                  ;; Non narrowed-case
                  (let ((all-files (directory-files
                                    dir
                                    t
                                    nil)))
                    ;; Filter directories
                    (unless directory-slideshow-include-directories?
                      (setq all-files (cl-remove-if (lambda (file)
                                                      (file-directory-p file))
                                                    all-files)))
                    ;; Filter speaker notes
                    (setq all-files (cl-remove-if (lambda (file)
                                                    (string-match-p (concat (regexp-quote directory-slideshow-speaker-notes-suffix)
                                                                            "$")
                                                                    file))
                                                  all-files))
                    (if directory-slideshow-ignore-regexp
                        (cl-remove-if (lambda (file)
                                        (string-match-p directory-slideshow-ignore-regexp
                                                        (file-name-nondirectory file)))
                                      all-files)
                      all-files)))))
    (sort slides directory-slideshow-file-name-sort-compare-fn)))

(defun directory-slideshow--cleanup ()
  "Clean up resources when the control buffer is killed."
  (when directory-slideshow--autoplay-timer
    (cancel-timer directory-slideshow--autoplay-timer)
    (setq-local directory-slideshow--autoplay-timer nil))
  (when (frame-live-p directory-slideshow--presentation-frame)
    (delete-frame directory-slideshow--presentation-frame))
  (directory-slideshow--cleanup-preview-window))

(defun directory-slideshow--unique-buffer-name ()
  "Return buffer name for a control buffer."
  (let ((prefix "*Directory Slideshow Control Panel")
        (suffix "*"))
    (if (null (get-buffer (concat prefix suffix)))
        (concat prefix suffix)
      (let ((n 2))
        (while (get-buffer (format "%s<%d>%s" prefix n suffix))
	  (setq n (1+ n)))
        (format "%s<%d>%s" prefix n suffix)))))

(defun directory-slideshow--slide-index-next ()
  "Retrieve the index of the next slide.
Respects next wrap-around preferences.  Returns NIL if at end of
the slideshow and `directory-slideshow-wrap-around?' is NIL."
  (let ((slide-count (length directory-slideshow--slides))
        (increment (pcase directory-slideshow-presentation-mode
                     ('chunk-two 2)
                     (_ 1))))
    (if directory-slideshow-wrap-around?
        (mod (+ increment directory-slideshow--current-index)
             slide-count)
      (let ((next-idx (+ increment directory-slideshow--current-index)))
        (when (< next-idx slide-count)
          next-idx)))))

(defun directory-slideshow--slide-index-prev ()
  "Retrieve the index of the previous slide.
Respects next wrap-around preferences.  Returns NIL if at
beginning of the slideshow and `directory-slideshow-wrap-around?'
is NIL."
  (let ((slide-count (length directory-slideshow--slides))
        (decrement (pcase directory-slideshow-presentation-mode
                     ('chunk-two 2)
                     (_ 1))))
    (if directory-slideshow-wrap-around?
        (mod (- directory-slideshow--current-index decrement)
             slide-count)
      (let ((next-idx (- directory-slideshow--current-index decrement)))
        (unless (< next-idx 0)
          next-idx)))))

(defun directory-slideshow--slide-index+1 ()
  "Retrieve the index just past the current slide.
Unlike `directory-slideshow--slide-index-next', ignores
`directory-slideshow-presentation-mode'."
  (let ((slide-count (length directory-slideshow--slides)))
    (if directory-slideshow-wrap-around?
        (mod (+ 1 directory-slideshow--current-index)
             slide-count)
      (let ((next-idx (+ 1 directory-slideshow--current-index)))
        (when (< next-idx slide-count)
          next-idx)))))

(defun directory-slideshow--slide-index+2 ()
  "Retrieve the index just past the current slide.
Unlike `directory-slideshow--slide-index-next', ignores
`directory-slideshow-presentation-mode'."
  (let ((slide-count (length directory-slideshow--slides)))
    (if directory-slideshow-wrap-around?
        (mod (+ 2 directory-slideshow--current-index)
             slide-count)
      (let ((next-idx (+ 2 directory-slideshow--current-index)))
        (when (< next-idx slide-count)
          next-idx)))))

(defun directory-slideshow--slide-index+3 ()
  "Retrieve the index just past the current slide.
Unlike `directory-slideshow--slide-index-next', ignores
`directory-slideshow-presentation-mode'."
  (let ((slide-count (length directory-slideshow--slides)))
    (if directory-slideshow-wrap-around?
        (mod (+ 3 directory-slideshow--current-index)
             slide-count)
      (let ((next-idx (+ 3 directory-slideshow--current-index)))
        (when (< next-idx slide-count)
          next-idx)))))

(defun directory-slideshow--slide-index-advance ()
  "Increment buffer-local `directory-slideshow--current-index'."
  (when-let (next-slide-index (directory-slideshow--slide-index-next))
    (setq-local directory-slideshow--current-index next-slide-index)))

(defun directory-slideshow--slide-index-retreat ()
  "Decrement buffer-local `directory-slideshow--current-index'.
If at beginning, wrap around."
  (when-let (prev-slide-index (directory-slideshow--slide-index-prev))
    (setq-local directory-slideshow--current-index prev-slide-index)))

(defun directory-slideshow--landscape-p ()
  "Is the current buffer an image with greater width than height?"
  (when (eq major-mode 'image-mode)
    (let* ((image-dimensions (image-size (image-get-display-property) :pixels))
           (width (car image-dimensions))
           (height (cdr image-dimensions)))
      (> width height))))

(defun directory-slideshow--render-presentation-frame (current-slide-file-name)
  "Render the presentation frame.
Use CURRENT-SLIDE-FILE-NAME to acquire the buffer context to make
transformations such as fitting images to the window."
  (save-selected-window
    (unless (and directory-slideshow--presentation-frame
                 (frame-live-p directory-slideshow--presentation-frame))
      (setq-local directory-slideshow--presentation-frame (directory-slideshow--make-presentation-frame))))
  (pcase directory-slideshow-presentation-mode
    ('one-slide-at-a-time
     (with-selected-frame directory-slideshow--presentation-frame
       (delete-other-windows)
       (find-file current-slide-file-name)
       (when (eq major-mode 'image-mode)
         (image-transform-fit-to-window))
       (run-hooks 'directory-slideshow-after-slide-render-hook)))

    ('chunk-two
     (if-let* ((second-slide-index (directory-slideshow--slide-index+1))
               (second-slide (nth second-slide-index directory-slideshow--slides)))
         (with-selected-frame directory-slideshow--presentation-frame
           (delete-other-windows)
           (let ((current-slide-buffer (find-file current-slide-file-name)))
             (let ((second-window (split-window-right)))
               (select-window second-window)
               (find-file second-slide)
               (when (eq major-mode 'image-mode)
                 (image-transform-fit-to-window))
               (run-hooks 'directory-slideshow-after-slide-render-hook))
             (with-current-buffer current-slide-buffer
               (when (eq major-mode 'image-mode)
                 (image-transform-fit-to-window))
               (run-hooks 'directory-slideshow-after-slide-render-hook))))
       (with-selected-frame directory-slideshow--presentation-frame
         (delete-other-windows)
         (find-file current-slide-file-name)
         (when (eq major-mode 'image-mode)
           (image-transform-fit-to-window))
         (run-hooks 'directory-slideshow-after-slide-render-hook))))

    ('sliding-window
     (if-let* ((second-slide-index (directory-slideshow--slide-index+1))
               (second-slide (nth second-slide-index directory-slideshow--slides)))
         (let ((atomic-landscape? directory-slideshow-atomic-landscape-images?))
           (with-selected-frame directory-slideshow--presentation-frame
             (delete-other-windows)
             (let ((current-slide-buffer (find-file current-slide-file-name)))
               (with-current-buffer current-slide-buffer
                 (unless (and atomic-landscape?
                              (directory-slideshow--landscape-p))
                   (let ((second-window (split-window-right)))
                     (select-window second-window)
                     (find-file second-slide)
                     (when (eq major-mode 'image-mode)
                       (image-transform-fit-to-window))
                     (run-hooks 'directory-slideshow-after-slide-render-hook))))
               (with-current-buffer current-slide-buffer
                 (when (eq major-mode 'image-mode)
                   (image-transform-fit-to-window))
                 (run-hooks 'directory-slideshow-after-slide-render-hook)))))
       (with-selected-frame directory-slideshow--presentation-frame
         (delete-other-windows)
         (find-file current-slide-file-name)
         (when (eq major-mode 'image-mode)
           (image-transform-fit-to-window))
         (run-hooks 'directory-slideshow-after-slide-render-hook))))

    (_
     (user-error "Unknown presentation mode %s" directory-slideshow-presentation-mode))))

(defun directory-slideshow--go-to-current-slide ()
  "Visit the slide indicated by `directory-slideshow--current-index'.
Occurs in the presentation frame."
  (let* ((current-slide-file-name (nth directory-slideshow--current-index
                                       directory-slideshow--slides))
         (speaker-notes-file-name (concat current-slide-file-name directory-slideshow-speaker-notes-suffix)))
    (setq-local directory-slideshow--speaker-notes (when (file-exists-p speaker-notes-file-name)
                                                     (with-temp-buffer
                                                       (insert-file-contents speaker-notes-file-name)
                                                       (buffer-string))))
    (directory-slideshow--render-control-buffer)
    (directory-slideshow--render-presentation-frame current-slide-file-name)))

(defun directory-slideshow--get-preview-buffer ()
  "Get buffer for preview window in control frame."
  (if (and (eq directory-slideshow-presentation-mode 'sliding-window)
           (not (and directory-slideshow-atomic-landscape-images?
                     (with-current-buffer (find-file-noselect (nth directory-slideshow--current-index
                                                                   directory-slideshow--slides))
                       (directory-slideshow--landscape-p)))))
      (cl-values
       (if-let (next-slide-index (directory-slideshow--slide-index+2))
           (find-file-noselect (nth next-slide-index directory-slideshow--slides))
         (let ((end-buffer (get-buffer-create "End Slideshow")))
           (with-current-buffer end-buffer
             (erase-buffer)
             (insert (propertize "THE END" 'face 'bold)))
           end-buffer))
       nil)
    (pcase directory-slideshow-presentation-mode
      ('chunk-two
       (if-let (next-slide-index (directory-slideshow--slide-index-next))
           (cl-values
            (find-file-noselect (nth next-slide-index directory-slideshow--slides))
            (when-let (after-slide-idx (directory-slideshow--slide-index+3))
              (find-file-noselect (nth after-slide-idx directory-slideshow--slides))))
         (let ((end-buffer (get-buffer-create "End Slideshow")))
           (with-current-buffer end-buffer
             (erase-buffer)
             (insert (propertize "THE END" 'face 'bold)))
           (cl-values end-buffer nil))))
      (_
       (cl-values
        (if-let (next-slide-index (directory-slideshow--slide-index-next))
            (find-file-noselect (nth next-slide-index directory-slideshow--slides))
          (let ((end-buffer (get-buffer-create "End Slideshow")))
            (with-current-buffer end-buffer
              (erase-buffer)
              (insert (propertize "THE END" 'face 'bold)))
            end-buffer))
        nil)))))

(defun directory-slideshow--yessify (x)
  "Turn X into \"yes\" or \"no\".
Non-NIL X values become yes."
  (if x "yes" "no"))

(defun directory-slideshow--insert-settings-menu ()
  "Insert settings menu into the current buffer."
  (insert-rectangle
   (list
    (concat (substitute-command-keys
             "\\[directory-slideshow-toggle-preview-next-slide]")
            " ⇒ Toggle Preview Next Slide"
            (propertize (format "〖%s〗" (directory-slideshow--yessify directory-slideshow-preview-next-slide?))
                        'face 'shadow))
    (concat (substitute-command-keys
             "\\[directory-slideshow-toggle-wrap-around]")
            " ⇒ Toggle Wrap Around"
            (propertize (format "〖%s〗" (directory-slideshow--yessify directory-slideshow-wrap-around?))
                        'face 'shadow))
    (concat (substitute-command-keys
             "\\[directory-slideshow-toggle-play]")
            " ⇒ Toggle Auto Play"
            (propertize (format "〖%s〗" (directory-slideshow--yessify directory-slideshow--autoplay-timer))
                        'face 'shadow))
    (concat (substitute-command-keys
             "\\[directory-slideshow-toggle-autoplay-direction]")
            " ⇒ Toggle Auto Play Direction"
            (propertize (format "〖%s〗" (if directory-slideshow--autoplay-reverse?
                                             "⇐"
                                           "⇒"))
                        'face 'shadow))
    (concat (substitute-command-keys
             "\\[directory-slideshow-set-autoplay-timer]")
            " ⇒ Set Auto Play Interval"
            (propertize (format "〖%s〗" directory-slideshow-autoplay-interval)
                        'face 'shadow))
    (concat (substitute-command-keys
             "\\[directory-slideshow-set-presentation-mode]")
            " ⇒ Set Presentation Mode"
            (propertize (format "〖%s〗" directory-slideshow-presentation-mode)
                        'face 'shadow))
    (concat (substitute-command-keys
             "\\[directory-slideshow-toggle-landscape-images]")
            " ⇒ Toggle Atomic Landscape Images"
            (propertize (format "〖%s〗" (directory-slideshow--yessify
                                          directory-slideshow-atomic-landscape-images?))
                        'face 'shadow)
            (propertize "    (Applies when in sliding-window mode)"
                        'face '(italic shadow)))))
  (align-regexp (point-min) (point-max) "\\(\\s-*\\)⇒")
  (align-regexp (point-min) (point-max) "\\(\\s-*\\)〖"))

(defun directory-slideshow--render-control-buffer ()
  "Rerender the contents of the control-buffer based on current state.
If passed, include SPEAKER-NOTES."
  (save-excursion
    (let ((inhibit-read-only t))
      (erase-buffer)
      (directory-slideshow--insert-settings-menu)
      (when directory-slideshow--speaker-notes
        (newline 2)
        (insert (propertize "Speaker Notes" 'face 'bold))
        (newline)
        (insert directory-slideshow--speaker-notes)))))

;; ┌───────┐
;; │ Setup │
;; └───────┘
(defvar directory-slideshow-mode-map
  (let ((map (make-sparse-keymap)))
    map)
  "Keymap for `directory-slideshow-mode'.")

(defun directory-slideshow--setup-keymap ()
  "Set up the keymap for `directory-slideshow-mode'."
  (when directory-slideshow-use-default-bindings
    (define-key directory-slideshow-mode-map (kbd "q") 'directory-slideshow-quit)
    (define-key directory-slideshow-mode-map (kbd "n") 'directory-slideshow-advance)
    (define-key directory-slideshow-mode-map (kbd "p") 'directory-slideshow-retreat)
    (define-key directory-slideshow-mode-map (kbd "u") 'directory-slideshow-toggle-preview-next-slide)
    (define-key directory-slideshow-mode-map (kbd "w") 'directory-slideshow-toggle-wrap-around)
    (define-key directory-slideshow-mode-map (kbd "k") 'directory-slideshow-toggle-autoplay-direction)
    (define-key directory-slideshow-mode-map (kbd "SPC") 'directory-slideshow-toggle-play)
    (define-key directory-slideshow-mode-map (kbd "a") 'directory-slideshow-set-autoplay-timer)
    (define-key directory-slideshow-mode-map (kbd "m") 'directory-slideshow-set-presentation-mode)
    (define-key directory-slideshow-mode-map (kbd "l") 'directory-slideshow-toggle-landscape-images)))

(directory-slideshow--setup-keymap)

(define-derived-mode directory-slideshow-mode special-mode "Directory Slideshow"
  "Major mode for controlling a presentation.")

(provide 'directory-slideshow)
;;; directory-slideshow.el ends here
