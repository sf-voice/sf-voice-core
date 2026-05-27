# @sf-voice/media

TypeScript SDK for the sf-voice media API.

Version: `0.1.1`

## Installation

```sh
pnpm add @sf-voice/media@latest
```

```sh
npm install @sf-voice/media@latest
```

```sh 
bun install @sf-voice/media@latest
```

## Usage

```ts
import { SfVoiceMedia, SfVoiceMediaError } from "@sf-voice/media";

const client = new SfVoiceMedia({
  baseUrl: "https://api.sf-voice.com",
  apiKey: process.env.SF_VOICE_API_KEY!,
});

// once you have the media file ready in S3 

try {
  const ingest = await client.ingest({
    source: "url",
    url: "https://example.com/recording.mp4",
    media_type: "video",
    metadata: { title: "product demo" },
  });



  if (task.status === "failed") {
    throw new Error(task.error ?? "ingest task failed");
  }

  const search = await client.search({
    query: "why are customers dropping calls",
    asset_ids: [task.asset_id],
    types: ["conversation"],
    threshold: 0.7,
  });

  console.log(search.results);
} catch (error) {
  if (error instanceof SfVoiceMediaError) {
    console.error(error.code, error.status, error.message);
  }
  throw error;
}
```

## API

The client exposes:

- `ingest(request)` - submit URL or S3 media for indexing.
- `getTask(taskId)` - fetch task state.
- `pollTask(taskId, options)` - wait until a task is `ready` or `failed`.
- `listAssets(params)` - list indexed assets.
- `getAsset(id)` - fetch one asset.
- `deleteAsset(id)` - soft-delete an asset.
- `search(request)` - search indexed media with natural language.

## Examples

- [`fifteenlabs`](../../apps/fifteenlabs) - browser ingest and search demo.
