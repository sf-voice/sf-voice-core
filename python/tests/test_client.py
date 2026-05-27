import json
import unittest

import httpx

from sf_voice import (
    AsyncSfVoiceMedia,
    SfVoiceMedia,
    SfVoiceMediaError,
    SfVoiceMediaPollTimeoutError,
    SfVoiceMediaRequestTimeoutError,
)


API_BASE_URL = "https://api.example.test"


def _ingest_response() -> dict:
    return {
        "asset_id": "video_123",
        "task_id": "task_123",
        "status": "pending",
    }


def _task_response(status: str = "ready") -> dict:
    return {
        "task_id": "task_123",
        "asset_id": "video_123",
        "asset_class": "customer_acme",
        "types": ["video", "transcript"],
        "status": status,
        "created_at": "2026-05-27T12:00:00Z",
    }


class SfVoiceMediaClientTests(unittest.TestCase):
    def test_ingest_url_sends_request_object(self) -> None:
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["method"] = request.method
            seen["path"] = request.url.path
            seen["headers"] = request.headers
            seen["body"] = json.loads(request.read())
            return httpx.Response(202, json=_ingest_response())

        client = SfVoiceMedia(
            base_url=API_BASE_URL,
            api_key="sk_test",
            transport=httpx.MockTransport(handler),
        )

        response = client.ingest(
            {
                "source": "url",
                "asset_id": "video_123",
                "asset_class": "customer_acme",
                "url": "https://example.com/video.mp4",
                "media_type": "video",
                "types": ["video", "transcript"],
                "metadata": {"title": "demo"},
            }
        )

        self.assertEqual(response.asset_id, "video_123")
        self.assertEqual(seen["method"], "POST")
        self.assertEqual(seen["path"], "/v1/ingest")
        self.assertEqual(seen["headers"]["x-api-key"], "sk_test")
        self.assertEqual(seen["headers"]["content-type"], "application/json")
        self.assertEqual(
            seen["body"],
            {
                "source": "url",
                "asset_id": "video_123",
                "asset_class": "customer_acme",
                "url": "https://example.com/video.mp4",
                "media_type": "video",
                "types": ["video", "transcript"],
                "metadata": {"title": "demo"},
            },
        )

    def test_ingest_file_sends_multipart(self) -> None:
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["content_type"] = request.headers["content-type"]
            seen["body"] = request.read()
            return httpx.Response(202, json=_ingest_response())

        client = SfVoiceMedia(
            base_url=API_BASE_URL,
            api_key="sk_test",
            transport=httpx.MockTransport(handler),
        )

        client.ingest(
            {
                "source": "file",
                "asset_id": "video_123",
                "asset_class": "customer_acme",
                "file": b"hello",
                "filename": "demo.mp4",
                "content_type": "video/mp4",
                "media_type": "video",
                "types": ["video", "transcript"],
                "metadata": {"title": "demo"},
            }
        )

        self.assertTrue(seen["content_type"].startswith("multipart/form-data"))
        self.assertIn(b'name="source"\r\n\r\nfile', seen["body"])
        self.assertIn(b'name="asset_id"\r\n\r\nvideo_123', seen["body"])
        self.assertIn(b'name="types"\r\n\r\n["video","transcript"]', seen["body"])
        self.assertIn(b'name="metadata"\r\n\r\n{"title":"demo"}', seen["body"])
        self.assertIn(b'filename="demo.mp4"', seen["body"])
        self.assertIn(b"hello", seen["body"])

    def test_search_sends_request_object(self) -> None:
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["body"] = json.loads(request.read())
            return httpx.Response(
                200,
                json={
                    "results": [
                        {
                            "asset_id": "video_123",
                            "score": 0.9,
                            "start_ms": 1000,
                            "end_ms": 2000,
                            "match_type": "transcript",
                        }
                    ],
                    "page_info": {
                        "total": 1,
                        "page": 1,
                        "limit": 10,
                        "next_page_token": "2",
                    },
                },
            )

        client = SfVoiceMedia(
            base_url=API_BASE_URL,
            api_key="sk_test",
            transport=httpx.MockTransport(handler),
        )

        response = client.search(
            {
                "query": "pricing",
                "asset_class": "customer_acme",
                "scope": "all",
                "types": ["transcript"],
                "threshold": 0.7,
                "page": 1,
                "limit": 10,
            }
        )

        self.assertEqual(response.results[0].match_type, "transcript")
        self.assertEqual(response.page_info.next_page_token, "2")
        self.assertEqual(
            seen["body"],
            {
                "query": "pricing",
                "asset_class": "customer_acme",
                "scope": "all",
                "types": ["transcript"],
                "threshold": 0.7,
                "page": 1,
                "limit": 10,
            },
        )

    def test_path_params_are_encoded(self) -> None:
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["path"] = request.url.raw_path.decode("ascii")
            return httpx.Response(200, json=_task_response())

        client = SfVoiceMedia(
            base_url=API_BASE_URL,
            api_key="sk_test",
            transport=httpx.MockTransport(handler),
        )

        client.get_task("task/with space")

        self.assertEqual(seen["path"], "/v1/tasks/task%2Fwith%20space")

    def test_error_envelope_raises_sdk_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(
                404,
                json={"error": {"code": "not_found", "message": "missing asset"}},
            )

        client = SfVoiceMedia(
            base_url=API_BASE_URL,
            api_key="sk_test",
            transport=httpx.MockTransport(handler),
        )

        with self.assertRaises(SfVoiceMediaError) as raised:
            client.get_asset("video_123")

        self.assertEqual(raised.exception.code, "not_found")
        self.assertEqual(raised.exception.message, "missing asset")
        self.assertEqual(raised.exception.status, 404)

    def test_request_timeout_raises_typed_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ReadTimeout("slow", request=request)

        client = SfVoiceMedia(
            base_url=API_BASE_URL,
            api_key="sk_test",
            timeout_ms=50,
            transport=httpx.MockTransport(handler),
        )

        with self.assertRaises(SfVoiceMediaRequestTimeoutError) as raised:
            client.get_task("task_123")

        self.assertEqual(raised.exception.timeout_ms, 50)

    def test_poll_timeout_raises_typed_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json=_task_response(status="pending"))

        client = SfVoiceMedia(
            base_url=API_BASE_URL,
            api_key="sk_test",
            transport=httpx.MockTransport(handler),
        )

        with self.assertRaises(SfVoiceMediaPollTimeoutError) as raised:
            client.poll_task("task_123", {"interval_ms": 1, "timeout_ms": 2})

        self.assertEqual(raised.exception.task_id, "task_123")
        self.assertEqual(raised.exception.timeout_ms, 2)


class AsyncSfVoiceMediaClientTests(unittest.IsolatedAsyncioTestCase):
    async def test_async_ingest_url_sends_request_object(self) -> None:
        seen = {}

        async def handler(request: httpx.Request) -> httpx.Response:
            seen["body"] = json.loads(request.read())
            return httpx.Response(202, json=_ingest_response())

        async with AsyncSfVoiceMedia(
            base_url=API_BASE_URL,
            api_key="sk_test",
            transport=httpx.MockTransport(handler),
        ) as client:
            response = await client.ingest(
                {
                    "source": "url",
                    "asset_id": "video_123",
                    "url": "https://example.com/video.mp4",
                }
            )

        self.assertEqual(response.task_id, "task_123")
        self.assertEqual(
            seen["body"],
            {
                "source": "url",
                "asset_id": "video_123",
                "url": "https://example.com/video.mp4",
            },
        )


if __name__ == "__main__":
    unittest.main()
