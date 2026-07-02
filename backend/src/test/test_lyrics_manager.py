import json
import unittest

import lyrics_manager
from lyrics_manager import LRCLIB_TIMEOUT, LYRICS_RETRY_INTERVAL, LyricsManager


class LyricsManagerTest(unittest.TestCase):
    def test_lrclib_search_uses_longer_timeout_and_parses_synced_lyrics(self):
        manager = LyricsManager()
        calls = []

        def fake_http_get(url, timeout=5):
            calls.append((url, timeout))
            if "/api/search?" in url and "track_name=" in url:
                return 200, json.dumps([
                    {"syncedLyrics": "[00:01.00]first line\n[00:02.50]second line"}
                ])
            return 404, ""

        manager._http_get = fake_http_get

        lyrics = manager._fetch_lyrics_lrclib("Title", "Artist", "Album", 226000000)

        self.assertEqual(
            lyrics,
            [
                {"time_ms": 1000000, "lyric": "first line"},
                {"time_ms": 2500000, "lyric": "second line"},
            ],
        )
        self.assertTrue(calls)
        self.assertTrue(all(timeout == LRCLIB_TIMEOUT for _, timeout in calls))


    def test_failed_fetch_retries_after_interval(self):
        manager = LyricsManager()
        track_info = {
            "title": "Title",
            "artist": ["Artist"],
            "album": "Album",
            "length": 1000000,
        }
        track_key = manager._track_key("org.mpris.MediaPlayer2.spotify", track_info)
        starts = []
        now = [100.0]

        def fake_monotonic():
            return now[0]

        def fake_start(playername, info, key):
            starts.append((playername, key))
            manager._last_fetch_attempts[key] = fake_monotonic()

        original_monotonic = lyrics_manager.time.monotonic
        try:
            lyrics_manager.time.monotonic = fake_monotonic
            manager._start_lyrics_fetch = fake_start

            self.assertTrue(manager._should_retry_lyrics_fetch(track_key))
            manager._start_lyrics_fetch("org.mpris.MediaPlayer2.spotify", track_info, track_key)
            self.assertFalse(manager._should_retry_lyrics_fetch(track_key))

            now[0] += LYRICS_RETRY_INTERVAL
            self.assertTrue(manager._should_retry_lyrics_fetch(track_key))
        finally:
            lyrics_manager.time.monotonic = original_monotonic


if __name__ == "__main__":
    unittest.main()
