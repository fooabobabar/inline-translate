# inline-translate.el

Inline translation overlays for Emacs, powered by [Ollama](https://ollama.com/) (local) or the [Anthropic Claude API](https://www.anthropic.com/).

Translations appear directly below the source text as buffer overlays — no pop-ups, no side windows.

## Features

- **Overlay mode** — translation shown inline beneath the source text, source untouched
- **Rewrite mode** — source text replaced in-place with its translation
- **Two backends** — Ollama for local/offline use, Claude for cloud quality
- **DWIM commands** — operate on the active region or fall back to the current paragraph automatically

## Requirements

- Emacs 27.1+
- For Ollama backend: a running Ollama instance (default: `http://localhost:11434`)
- For Claude backend: an `ANTHROPIC_API_KEY` environment variable (or custom key function)

## Installation

Clone the repo and add it to your load path:

```emacs-lisp
(add-to-list 'load-path "/path/to/inline-translate")
(require 'inline-translate)
```

With `use-package`:

```emacs-lisp
(use-package inline-translate
  :load-path "/path/to/inline-translate")
```

## Usage

| Command | Description |
|---|---|
| `M-x inline-translate-dwim` | Translate region or paragraph → overlay |
| `M-x inline-translate-region` | Translate active region → overlay |
| `M-x inline-translate-paragraph` | Translate current paragraph → overlay |
| `M-x inline-translate-clear-all` | Remove all overlays from the buffer |
| `M-x inline-translate-clear-at-point` | Remove overlay at point |
| `M-x inline-translate-rewrite-dwim` | Translate region or paragraph → replace in place |
| `M-x inline-translate-rewrite-region` | Translate active region → replace in place |
| `M-x inline-translate-rewrite-paragraph` | Translate current paragraph → replace in place |

Suggested keybindings:

```emacs-lisp
(global-set-key (kbd "C-c t t") #'inline-translate-dwim)
(global-set-key (kbd "C-c t c") #'inline-translate-clear-all)
(global-set-key (kbd "C-c t r") #'inline-translate-rewrite-dwim)
```

## Configuration

```emacs-lisp
;; Choose backend: 'ollama (default) or 'claude
(setq inline-translate-backend 'claude)

;; Target language for overlay translations (default: "Portuguese (Brazil)")
(setq inline-translate-target-language "Spanish")

;; Target language for in-place rewrites (default: "English")
(setq inline-translate-rewrite-language "French")
```

### Ollama options

```emacs-lisp
(setq inline-translate-ollama-endpoint "http://localhost:11434/api/generate")
(setq inline-translate-ollama-model "llama3.1")
```

### Claude options

```emacs-lisp
(setq inline-translate-claude-model "claude-sonnet-4-6")

;; API key — defaults to the ANTHROPIC_API_KEY environment variable.
;; Override with a string or a zero-argument function:
(setq inline-translate-claude-api-key "sk-ant-...")
(setq inline-translate-claude-api-key (lambda () (password-store-get "anthropic/api-key")))
```

## License

This project is in the public domain (or use it under whatever terms suit you).
