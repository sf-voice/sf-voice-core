# fraud prototype

Local phone-line fraud prototype using Fastify, Telnyx call control, and a
minimal scammer-call harness.

## setup

```bash
cp .env.example .env
# fill in TELNYX_API_KEY, TELNYX_CONNECTION_ID, PHONE_NUMBER, and PUBLIC_URL
```

`TELNYX_PUBLIC_KEY` is optional for local testing, but production webhooks must
verify signatures. Telnyx signs webhooks with the `telnyx-signature-ed25519` and
`telnyx-timestamp` headers over `timestamp|raw_body`.

## smoke check

```bash
bun run typecheck
```

## run

```bash
bun run dev
```

## dial test

This places an outbound call through Telnyx.

```bash
bun run scammer -- --to +15551234567 --script gift_cards_grandparent
```
