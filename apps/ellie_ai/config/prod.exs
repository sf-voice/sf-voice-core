import Config

# nothing to configure at compile time for prod — all production knobs live
# in runtime.exs, which is read after the release boots and after env vars
# (PHX_HOST, SECRET_KEY_BASE, PORT, ...) are available.
