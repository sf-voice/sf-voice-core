# sf-voice Python example

Sync and async CLI demo for the Python SDK.

## setup

```bash
cp .env.example .env
# fill in SF_VOICE_API_KEY
```

## smoke check

```bash
python3 -m compileall -q sf_voice_py
```

## run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
sf_voice_py demo "https://example.com/recording.mp4" "product launch"
```
