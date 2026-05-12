// ellie staff ui — esbuild entry. bundled into priv/static/assets/js/app.js
// by `mix esbuild ellie_ai` (watcher runs in dev).

import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

// SaladUI hooks. each side-effect import (dialog, tabs, dropdown_menu...)
// self-registers a custom element with the SaladUI factory. SaladUIHook
// is the single liveview hook that bridges all of them.
import SaladUI from "./ui/index.js"
import "./ui/components/command.js"
import "./ui/components/dialog.js"
import "./ui/components/dropdown_menu.js"
import "./ui/components/popover.js"
import "./ui/components/select.js"
import "./ui/components/tabs.js"
import "./ui/components/tooltip.js"

import PromptEditor from "./hooks/prompt_editor.js"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content")

// auto-dismiss toast after 5s. clicking dismisses immediately (handled
// by phx-click on the element itself). reduced-motion users still get
// the timer — no animation, just goes away.
const Toast = {
  mounted() {
    this.timer = setTimeout(() => {
      this.el.dispatchEvent(new Event("click", { bubbles: true }))
    }, 5000)
  },
  destroyed() {
    clearTimeout(this.timer)
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { SaladUI: SaladUI.SaladUIHook, Toast, PromptEditor },
})

liveSocket.connect()
window.liveSocket = liveSocket

// dev-time quality of life: stream server logs into the browser console,
// click-to-jump-to-definition with `c` / `d` modifier keys.
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", e => (keyDown = e.key))
    window.addEventListener("keyup", () => (keyDown = null))
    window.addEventListener(
      "click",
      e => {
        if (keyDown === "c") {
          e.preventDefault()
          e.stopImmediatePropagation()
          reloader.openEditorAtCaller(e.target)
        } else if (keyDown === "d") {
          e.preventDefault()
          e.stopImmediatePropagation()
          reloader.openEditorAtDef(e.target)
        }
      },
      true,
    )

    window.liveReloader = reloader
  })
}
