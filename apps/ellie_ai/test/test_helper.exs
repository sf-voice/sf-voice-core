# pin the telnyx public key to the committed dev keypair so SignaturePlug
# verifies bodies signed by TelnyxSigningHelper. without this, a stray
# TELNYX_PUBLIC_KEY in the shell silently overrides priv/dev/ and every
# signed-fixture test 401s.
dev_pubkey =
  :code.priv_dir(:ellie_ai)
  |> Path.join("dev/telnyx_test_pubkey.b64")
  |> File.read!()
  |> String.trim()

Application.put_env(:ellie_ai, :telnyx_public_key, dev_pubkey)

ExUnit.start(exclude: [:llm_eval])
Ecto.Adapters.SQL.Sandbox.mode(EllieAi.Repo, :manual)
