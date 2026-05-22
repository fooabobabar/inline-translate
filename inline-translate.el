;;; inline-translate.el --- Inline translation overlays via Ollama or Claude  -*- lexical-binding: t; -*-

;; Author: Lucas Fellipe
;; Version: 0.1
;; Keywords: translation, ai, ollama, claude
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:
;;
;; Show the translation of the selected text (or the current paragraph)
;; right below the source line, using an overlay with `after-string'.
;; The translation backend can be Ollama (local) or the Anthropic API.
;;
;; Basic usage:
;;   M-x inline-translate-region       (with an active region)
;;   M-x inline-translate-paragraph    (paragraph at point)
;;   M-x inline-translate-clear-all    (remove every overlay)
;;
;; Configure the backend:
;;   (setq inline-translate-backend 'ollama) ;; or 'claude
;;   (setq inline-translate-target-language "Portuguese (Brazil)")

;;; Code:

(require 'url)
(require 'json)

(defgroup inline-translate nil
  "Inline translation overlays."
  :group 'tools)

(defcustom inline-translate-backend 'ollama
  "Backend used for translation. Either `ollama' or `claude'."
  :type '(choice (const :tag "Ollama (local)" ollama)
                 (const :tag "Claude (Anthropic API)" claude))
  :group 'inline-translate)

(defcustom inline-translate-target-language "Portuguese (Brazil)"
  "Target language for translations."
  :type 'string
  :group 'inline-translate)

(defcustom inline-translate-ollama-endpoint "http://localhost:11434/api/generate"
  "Endpoint of the Ollama API."
  :type 'string
  :group 'inline-translate)

(defcustom inline-translate-ollama-model "llama3.1"
  "Ollama model to use."
  :type 'string
  :group 'inline-translate)

(defcustom inline-translate-claude-endpoint "https://api.anthropic.com/v1/messages"
  "Endpoint of the Anthropic API."
  :type 'string
  :group 'inline-translate)

(defcustom inline-translate-claude-model "claude-sonnet-4-6"
  "Anthropic model to use."
  :type 'string
  :group 'inline-translate)

(defcustom inline-translate-claude-api-key
  (lambda () (getenv "ANTHROPIC_API_KEY"))
  "Function (or string) returning the Anthropic API key.
Defaults to reading the ANTHROPIC_API_KEY environment variable."
  :type '(choice function string)
  :group 'inline-translate)

(defface inline-translate-face
  '((t :background "#181818"
       :foreground "#95a99f"
       :extend t))
  "Face used for the translated text displayed in the overlay."
  :group 'inline-translate)

(defvar-local inline-translate--overlays nil
  "List of active translation overlays in the buffer.")

(defun inline-translate--make-overlay (beg end translation)
  "Create an overlay between beg and end displaying translation below the line."
  (let* ((ov (make-overlay beg end))
         ;; Compute the indentation of the source line so the translation
         ;; lines up nicely underneath it.
         (indent (save-excursion
                   (goto-char beg)
                   (current-indentation)))
         (prefix (make-string indent ?\s))
         ;; Wrap the text so it does not stretch into a single huge line.
         (wrapped (inline-translate--wrap-text translation 80 prefix))
         (display-text
          (concat ""
                  (propertize (concat prefix wrapped "\n")
                              'face 'inline-translate-face))))
    (overlay-put ov 'inline-translate t)
    (overlay-put ov 'after-string display-text)
    (overlay-put ov 'help-echo (format "Translation: %s" translation))
    (push ov inline-translate--overlays)
    ov))

(defun inline-translate--wrap-text (text width prefix)
  "Wrap text into lines of up to width columns, prefixing each new line with prefix."
  (with-temp-buffer
    (insert text)
    (let ((fill-column width)
          (fill-prefix prefix))
      (fill-region (point-min) (point-max)))
    (buffer-string)))

(defun inline-translate-clear-all ()
  "Remove every translation overlay from the current buffer."
  (interactive)
  (dolist (ov inline-translate--overlays)
    (when (overlayp ov) (delete-overlay ov)))
  (setq inline-translate--overlays nil)
  (message "inline-translate: overlays cleared."))

(defun inline-translate-clear-at-point ()
  "Remove the translation overlay at point, if any."
  (interactive)
  (let ((ovs (overlays-at (point))))
    (dolist (ov ovs)
      (when (overlay-get ov 'inline-translate)
        (setq inline-translate--overlays (delq ov inline-translate--overlays))
        (delete-overlay ov)))))

(defun inline-translate--build-prompt (text)
  "Build the translation prompt for text."
  (format
   "Translate the following text to %s. Output ONLY the translation, with no preamble, no quotes, no explanations.\n\nText:\n%s"
   inline-translate-target-language
   text))

(defun inline-translate--ollama-request (text callback)
  "Send text to Ollama and invoke callback with the translation."
  (let* ((url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/json")))
         (payload `(("model"  . ,inline-translate-ollama-model)
                    ("prompt" . ,(inline-translate--build-prompt text))
                    ("stream" . :json-false)))
         (url-request-data
          (encode-coding-string (json-encode payload) 'utf-8)))
    (url-retrieve
     inline-translate-ollama-endpoint
     (lambda (status)
       (if (plist-get status :error)
           (funcall callback nil (format "Ollama error: %S" (plist-get status :error)))
         ;; Decode the response body as UTF-8 so accented characters render
         ;; correctly. `url-retrieve' delivers raw bytes in a unibyte buffer.
         (set-buffer-multibyte t)
         (decode-coding-region url-http-end-of-headers (point-max) 'utf-8)
         (goto-char url-http-end-of-headers)
         (let* ((json-object-type 'alist)
                (json-array-type 'list)
                (response (json-read))
                (translated (alist-get 'response response)))
           (kill-buffer (current-buffer))
           (if translated
               (funcall callback (string-trim translated) nil)
             (funcall callback nil "Response is missing the 'response' field.")))))
     nil t t)))

(defun inline-translate--claude-request (text callback)
  "Send text to the Anthropic API and invoke callback with the translation."
  (let* ((api-key (if (functionp inline-translate-claude-api-key)
                      (funcall inline-translate-claude-api-key)
                    inline-translate-claude-api-key))
         (_ (unless (and api-key (not (string-empty-p api-key)))
              (error "ANTHROPIC_API_KEY is not configured")))
         (url-request-method "POST")
         (url-request-extra-headers
          `(("Content-Type"      . "application/json")
            ("x-api-key"         . ,api-key)
            ("anthropic-version" . "2023-06-01")))
         (payload
          `(("model"      . ,inline-translate-claude-model)
            ("max_tokens" . 1024)
            ("messages"   . [(("role"    . "user")
                              ("content" . ,(inline-translate--build-prompt text)))])))
         (url-request-data
          (encode-coding-string (json-encode payload) 'utf-8)))
    (url-retrieve
     inline-translate-claude-endpoint
     (lambda (status)
       (if (plist-get status :error)
           (funcall callback nil (format "Claude error: %S" (plist-get status :error)))
         ;; Decode the response body as UTF-8 so accented characters render
         ;; correctly. `url-retrieve' delivers raw bytes in a unibyte buffer.
         (set-buffer-multibyte t)
         (decode-coding-region url-http-end-of-headers (point-max) 'utf-8)
         (goto-char url-http-end-of-headers)
         (let* ((json-object-type 'alist)
                (json-array-type 'list)
                (response (json-read))
                (content (alist-get 'content response))
                (translated (and content
                                 (alist-get 'text (car content)))))
           (kill-buffer (current-buffer))
           (if translated
               (funcall callback (string-trim translated) nil)
             (funcall callback nil
                      (format "Unexpected response: %S" response))))))
     nil t t)))

(defun inline-translate--dispatch (text callback)
  "Send text to the configured backend and call callback with the response."
  (pcase inline-translate-backend
    ('ollama (inline-translate--ollama-request text callback))
    ('claude (inline-translate--claude-request text callback))
    (other   (error "Unknown backend: %S" other))))

;;;###autoload
(defun inline-translate-region (beg end)
  "Translate the region between beg and end and show the result as an overlay."
  (interactive "r")
  (let ((text (buffer-substring-no-properties beg end))
        (buf  (current-buffer)))
    (when (string-empty-p (string-trim text))
      (user-error "Nothing to translate"))
    (message "inline-translate: translating with %s..." inline-translate-backend)
    (inline-translate--dispatch
     text
     (lambda (translation err)
       (with-current-buffer buf
         (cond
          (err (message "inline-translate: %s" err))
          ((not translation) (message "inline-translate: no response"))
          (t (inline-translate--make-overlay beg end translation)
             (message "inline-translate: done."))))))))

;;;###autoload
(defun inline-translate-paragraph ()
  "Translate the current paragraph."
  (interactive)
  (save-excursion
    (let (beg end)
      (backward-paragraph)
      (skip-chars-forward " \t\n")
      (setq beg (point))
      (forward-paragraph)
      (skip-chars-backward " \t\n")
      (setq end (point))
      (inline-translate-region beg end))))

;;;###autoload
(defun inline-translate-dwim ()
  "Translate the active region, or the current paragraph if no region is active."
  (interactive)
  (if (use-region-p)
      (inline-translate-region (region-beginning) (region-end))
    (inline-translate-paragraph)))

(defcustom inline-translate-rewrite-language "English"
  "Target language used by the in-place rewrite commands."
  :type 'string
  :group 'inline-translate)

(defun inline-translate--rewrite-region (beg end target-language)
  "Replace text between beg and end with its translation to target-language."
  (let* ((text (buffer-substring-no-properties beg end))
         (buf  (current-buffer))
         ;; Use markers so the positions stay valid even if the buffer
         ;; changes while we wait for the async response.
         (beg-marker (copy-marker beg))
         (end-marker (copy-marker end t))
         ;; Temporarily override the target language for this call.
         (inline-translate-target-language target-language))
    (when (string-empty-p (string-trim text))
      (user-error "Nothing to translate"))
    (message "inline-translate: rewriting to %s with %s..."
             target-language inline-translate-backend)
    (inline-translate--dispatch
     text
     (lambda (translation err)
       (with-current-buffer buf
         (cond
          (err (message "inline-translate: %s" err))
          ((not translation) (message "inline-translate: no response"))
          (t (save-excursion
               (goto-char beg-marker)
               (delete-region beg-marker end-marker)
               (insert translation))
             (message "inline-translate: rewritten."))))
       (set-marker beg-marker nil)
       (set-marker end-marker nil)))))

;;;###autoload
(defun inline-translate-rewrite-region (beg end)
  "Replace the region between beg and end with its translation.
The target language is `inline-translate-rewrite-language' (English by default)."
  (interactive "r")
  (inline-translate--rewrite-region beg end inline-translate-rewrite-language))

;;;###autoload
(defun inline-translate-rewrite-paragraph ()
  "Replace the current paragraph with its translation."
  (interactive)
  (save-excursion
    (let (beg end)
      (backward-paragraph)
      (skip-chars-forward " \t\n")
      (setq beg (point))
      (forward-paragraph)
      (skip-chars-backward " \t\n")
      (setq end (point))
      (inline-translate--rewrite-region beg end
                                        inline-translate-rewrite-language))))
;;;###autoload
(defun inline-translate-rewrite-dwim ()
  "Rewrite the active region, or the current paragraph if no region is active."
  (interactive)
  (if (use-region-p)
      (inline-translate-rewrite-region (region-beginning) (region-end))
    (inline-translate-rewrite-paragraph)))

(provide 'inline-translate)
;;; inline-translate.el ends here
