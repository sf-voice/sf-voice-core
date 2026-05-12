// prompt editor hook. attaches two behaviors to a wrapper that holds:
//
//   - a <textarea> the operator types the prompt body into
//   - a [data-prompt-preview] element where the rendered Liquid lands
//
// behavior 1 — autocomplete: when the operator types `{{` we pop a
// small dropdown of available variables next to the textarea. arrow
// keys to nav, Enter / Tab to insert, Esc to cancel. inserts the
// canonical `{{ org.name }}` shape so server-side rendering matches.
//
// behavior 2 — live preview: every input event re-renders the
// textarea body through liquidjs with the current org as context.
// rendering errors land in the preview block with state=error so
// the operator can spot a typo before saving.
//
// the variable list comes from data-prompt-vars (JSON array of
// {label, value}) and the preview context from data-prompt-context
// (JSON object). both are set server-side from the LiveView assigns.

import { Liquid } from "../../vendor/liquidjs.js"

const liquid = new Liquid()

const PromptEditor = {
  mounted() {
    this.textarea = this.el.querySelector("textarea")
    this.preview = this.el.querySelector("[data-prompt-preview]")
    this.variables = JSON.parse(this.el.dataset.promptVars || "[]")
    this.context = JSON.parse(this.el.dataset.promptContext || "{}")

    this.popup = null
    this.filtered = []
    this.activeIndex = 0

    this.onInput = () => {
      this.renderPreview()
      this.maybeShowPopup()
    }
    this.onKeydown = e => this.handleKeydown(e)
    // small delay so a click inside the popup lands before we close it
    this.onBlur = () => setTimeout(() => this.closePopup(), 120)

    this.textarea.addEventListener("input", this.onInput)
    this.textarea.addEventListener("keydown", this.onKeydown)
    this.textarea.addEventListener("blur", this.onBlur)

    this.renderPreview()
  },

  updated() {
    // server pushed new content (e.g. operator clicked "Restore" on a
    // prior version). re-read data attrs in case the context changed too.
    this.variables = JSON.parse(this.el.dataset.promptVars || "[]")
    this.context = JSON.parse(this.el.dataset.promptContext || "{}")
    this.renderPreview()
  },

  destroyed() {
    this.textarea.removeEventListener("input", this.onInput)
    this.textarea.removeEventListener("keydown", this.onKeydown)
    this.textarea.removeEventListener("blur", this.onBlur)
    this.closePopup()
  },

  async renderPreview() {
    if (!this.preview) return
    try {
      const out = await liquid.parseAndRender(this.textarea.value, this.context)
      this.preview.textContent = out
      this.preview.dataset.state = "ok"
    } catch (err) {
      this.preview.textContent = `preview error: ${err.message}`
      this.preview.dataset.state = "error"
    }
  },

  // look for an open `{{` token immediately before the cursor — that's
  // our "operator is typing a variable" signal. close popup if the
  // pattern doesn't match (e.g. operator backspaced over the braces).
  maybeShowPopup() {
    const cursor = this.textarea.selectionStart
    const before = this.textarea.value.slice(0, cursor)
    const match = before.match(/\{\{\s*([\w.]*)$/)

    if (!match) {
      this.closePopup()
      return
    }

    const query = match[1].toLowerCase()
    this.filtered = this.variables.filter(
      v => v.value.toLowerCase().includes(query) || v.label.toLowerCase().includes(query),
    )

    if (this.filtered.length === 0) {
      this.closePopup()
      return
    }

    this.activeIndex = 0
    this.openPopup()
  },

  openPopup() {
    if (!this.popup) {
      this.popup = document.createElement("div")
      this.popup.setAttribute("role", "listbox")
      this.popup.className = [
        "absolute",
        "z-50",
        "min-w-[220px]",
        "rounded-md",
        "border",
        "border-border",
        "bg-popover",
        "shadow-md",
        "py-1",
        "text-sm",
      ].join(" ")
      this.el.appendChild(this.popup)
    }

    // position relative to the textarea — left edge aligned, just below.
    // getting the actual caret position needs a mirrored div hack; for
    // a small prompt textarea this is good enough and far simpler.
    const taRect = this.textarea.getBoundingClientRect()
    const wrapRect = this.el.getBoundingClientRect()
    this.popup.style.left = `${taRect.left - wrapRect.left + 8}px`
    this.popup.style.top = `${taRect.bottom - wrapRect.top + 4}px`

    this.renderPopup()
  },

  renderPopup() {
    this.popup.innerHTML = this.filtered
      .map(
        (v, i) => `
          <div
            class="prompt-editor-item flex items-center justify-between gap-3 px-3 py-1.5 cursor-pointer ${
              i === this.activeIndex ? "bg-secondary" : ""
            }"
            data-index="${i}"
            role="option"
            aria-selected="${i === this.activeIndex}"
          >
            <span class="text-foreground font-medium">${escapeHtml(v.label)}</span>
            <span class="mono text-xs text-muted-foreground">{{ ${escapeHtml(v.value)} }}</span>
          </div>
        `,
      )
      .join("")

    this.popup.querySelectorAll(".prompt-editor-item").forEach(el => {
      // mousedown (not click) so we fire before the textarea's blur
      // cancels the popup.
      el.addEventListener("mousedown", e => {
        e.preventDefault()
        this.insertVariable(parseInt(el.dataset.index, 10))
      })
    })
  },

  closePopup() {
    if (this.popup) {
      this.popup.remove()
      this.popup = null
    }
    this.filtered = []
    this.activeIndex = 0
  },

  handleKeydown(e) {
    if (!this.popup || this.filtered.length === 0) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.activeIndex = (this.activeIndex + 1) % this.filtered.length
      this.renderPopup()
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.activeIndex =
        (this.activeIndex - 1 + this.filtered.length) % this.filtered.length
      this.renderPopup()
    } else if (e.key === "Enter" || e.key === "Tab") {
      e.preventDefault()
      this.insertVariable(this.activeIndex)
    } else if (e.key === "Escape") {
      e.preventDefault()
      this.closePopup()
    }
  },

  insertVariable(i) {
    const variable = this.filtered[i]
    if (!variable) return

    const cursor = this.textarea.selectionStart
    const before = this.textarea.value.slice(0, cursor)
    const after = this.textarea.value.slice(cursor)
    const match = before.match(/\{\{\s*([\w.]*)$/)
    if (!match) {
      this.closePopup()
      return
    }

    const start = cursor - match[0].length
    const replacement = `{{ ${variable.value} }}`
    this.textarea.value = before.slice(0, start) + replacement + after

    const newCursor = start + replacement.length
    this.textarea.setSelectionRange(newCursor, newCursor)
    this.textarea.focus()
    // synthesise input so phx-change (if wired) + preview both update
    this.textarea.dispatchEvent(new Event("input", { bubbles: true }))

    this.closePopup()
  },
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

export default PromptEditor
