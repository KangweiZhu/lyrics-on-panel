"""Offline regression tests: python -m unittest discover -s backend/src/test -p test_open_orpheus.py"""
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lyrics_manager import LyricsManager, open_orpheus_song_id
from mpris_player import PlaybackStatus


def track(song_id='2111993059'):
    return {'track_id': '/com/163/music/' + song_id, 'title': 'Same title',
            'artist': ['Artist'], 'album': 'Album', 'length': 10000000, 'url': ''}


def immediate_thread(*, target, args, **kwargs):
    return SimpleNamespace(start=lambda: target(*args))


class OpenOrpheusTests(unittest.TestCase):
    def setUp(self):
        self.manager = LyricsManager()

    def test_valid_ids_preserve_precision(self):
        for song_id in ('2111993059', '9007199254740993'):
            self.assertEqual(open_orpheus_song_id(track(song_id)), song_id)

    def test_invalid_ids_do_not_make_http_requests(self):
        with patch.object(self.manager, '_http_get') as http:
            for value in ('', '/org/mpris/MediaPlayer2/Track/1', '/com/163/music/0',
                          '/com/163/music/000', '/com/163/music/-1',
                          '/com/163/music/local_song', '/com/163/music/12?other=1'):
                self.assertIsNone(self.manager._fetch_lyrics_open_orpheus({'track_id': value}))
            http.assert_not_called()

    def test_request_parameters_and_lrc_timing(self):
        body = json.dumps({'code': 200, 'lrc': {'lyric': '[00:01]first\n[00:02]second'}})
        with patch.object(self.manager, '_http_get', return_value=(200, body)) as http:
            self.manager.lyrics = self.manager._fetch_lyrics_open_orpheus(track())
        url = urlparse(http.call_args.args[0])
        self.assertEqual((url.scheme, url.netloc, url.path),
                         ('https', 'music.163.com', '/api/song/lyric'))
        self.assertEqual(parse_qs(url.query), {'id': ['2111993059'], 'os': ['pc'],
                         **{key: ['-1'] for key in ('lv', 'kv', 'tv', 'yv', 'rv')}})
        self.manager.position_ms = 1500000
        self.assertEqual(self.manager._get_current_lyric(), 'first')
        self.manager.position_ms = 2000000
        self.assertEqual(self.manager._get_current_lyric(), 'second')

    def test_missing_lyrics_errors_and_malformed_responses(self):
        for status, body in ((500, ''), (None, None), (200, 'invalid json'),
                             (200, 'null'), (200, '[]'),
                             (200, '{"code":200,"nolyric":true}'),
                             (200, '{"code":200,"lrc":null}'),
                             (200, '{"code":404,"lrc":{"lyric":"[00:01]ignored"}}')):
            with self.subTest(body=body), patch.object(self.manager, '_http_get', return_value=(status, body)):
                self.assertIsNone(self.manager._fetch_lyrics_open_orpheus(track()))

    def test_id_only_track_uses_netease_without_lrclib(self):
        info = track()
        info.update(title='', artist=[])
        with patch.object(self.manager, '_fetch_lyrics_open_orpheus', return_value=[]) as fetch, \
                patch.object(self.manager, '_fetch_lyrics_lrclib') as lrclib:
            self.manager._fetch_lyrics('org.mpris.MediaPlayer2.open-orpheus',
                                       'Open Orpheus', info, self.manager._fetch_id)
            fetch.assert_called_once_with(info)
            lrclib.assert_not_called()

    def test_flatpak_selection_track_id_changes_and_cache(self):
        bus = 'org.mpris.MediaPlayer2.io.github.yucling.open-orpheus'
        player = SimpleNamespace(obj=True, identity='Open Orpheus', track_info=track('1'),
                                 playback_status=PlaybackStatus.PLAYING, position=2000000)
        lyrics = [{'time_ms': 1000000, 'lyric': 'first'}]
        with patch('lyrics_manager.find_players', return_value=[bus]), \
                patch('lyrics_manager.MprisPlayer', return_value=player), \
                patch('lyrics_manager.threading.Thread', side_effect=immediate_thread), \
                patch.object(self.manager, '_fetch_lyrics_open_orpheus', return_value=lyrics) as fetch:
            first = self.manager.poll_status('open-orpheus')
            self.assertEqual(first['player']['bus_name'], bus)
            self.assertEqual(first['lyrics']['current_lyric'], 'first')
            self.manager.poll_status('open-orpheus')
            self.assertEqual(fetch.call_count, 1)
            player.track_info = track('2')
            self.manager.poll_status('open-orpheus')
            self.assertEqual(fetch.call_count, 2)

    def test_absent_player_clears_state_and_invalidates_fetch(self):
        generation = self.manager._fetch_id
        self.manager.lyrics = [{'time_ms': 0, 'lyric': 'old'}]
        with patch('lyrics_manager.find_players', return_value=[]):
            self.assertIsNone(self.manager.poll_status('open-orpheus')['player'])
        self.assertGreater(self.manager._fetch_id, generation)
        self.assertIsNone(self.manager.lyrics)

    def test_mode_switch_changes_source_for_same_track(self):
        bus = 'org.mpris.MediaPlayer2.io.github.yucling.open-orpheus'
        player = SimpleNamespace(obj=True, identity='Open Orpheus', track_info=track(),
                                 playback_status=PlaybackStatus.PLAYING, position=2000000)
        netease = [{'time_ms': 0, 'lyric': 'NetEase'}]
        global_lyrics = [{'time_ms': 0, 'lyric': 'LrcLib'}]
        with patch('lyrics_manager.find_players', return_value=[bus]), \
                patch('lyrics_manager.MprisPlayer', return_value=player), \
                patch('lyrics_manager.threading.Thread', side_effect=immediate_thread), \
                patch.object(self.manager, '_fetch_lyrics_open_orpheus', return_value=netease) as fetch, \
                patch.object(self.manager, '_fetch_lyrics_lrclib', return_value=global_lyrics) as lrclib:
            self.assertEqual(self.manager.poll_status(bus)['lyrics']['current_lyric'], 'NetEase')
            self.assertEqual(self.manager.poll_status()['lyrics']['current_lyric'], 'LrcLib')
            self.assertEqual(self.manager.poll_status(bus)['lyrics']['current_lyric'], 'NetEase')
            # A player chosen manually in Global Mode still uses LrcLib.
            self.assertEqual(self.manager.poll_status(bus, global_mode=True)['lyrics']['current_lyric'], 'LrcLib')
            self.assertEqual(fetch.call_count, 2)
            self.assertEqual(lrclib.call_count, 2)

    def test_global_mode_requires_metadata_and_never_calls_netease(self):
        info = track()
        info.update(title='', artist=[])
        with patch.object(self.manager, '_fetch_lyrics_open_orpheus') as fetch:
            self.manager._fetch_lyrics('org.mpris.MediaPlayer2.open-orpheus',
                                      'Open Orpheus', info, self.manager._fetch_id,
                                      global_mode=True)
            fetch.assert_not_called()

    def test_explicit_service_does_not_fallback_to_other_installation(self):
        native = 'org.mpris.MediaPlayer2.open-orpheus'
        flatpak = 'org.mpris.MediaPlayer2.io.github.yucling.open-orpheus'
        with patch('lyrics_manager.find_players', return_value=[flatpak]), \
                patch('lyrics_manager.MprisPlayer') as player:
            self.assertIsNone(self.manager.poll_status(native)['player'])
            player.assert_not_called()

    def test_explicit_service_selects_requested_instance(self):
        native = 'org.mpris.MediaPlayer2.open-orpheus'
        flatpak = 'org.mpris.MediaPlayer2.io.github.yucling.open-orpheus'
        player = SimpleNamespace(obj=True, identity='Open Orpheus', track_info=track(),
                                 playback_status=PlaybackStatus.PAUSED, position=0)
        with patch('lyrics_manager.find_players', return_value=[native, flatpak]), \
                patch('lyrics_manager.MprisPlayer', return_value=player) as create, \
                patch('lyrics_manager.threading.Thread'):
            self.assertEqual(self.manager.poll_status(flatpak)['player']['bus_name'], flatpak)
            create.assert_called_once_with(flatpak)

    def test_failed_fetch_is_retried_after_backoff(self):
        bus = 'org.mpris.MediaPlayer2.open-orpheus'
        player = SimpleNamespace(obj=True, identity='Open Orpheus', track_info=track(),
                                 playback_status=PlaybackStatus.PAUSED, position=0)
        with patch('lyrics_manager.find_players', return_value=[bus]), \
                patch('lyrics_manager.MprisPlayer', return_value=player), \
                patch('lyrics_manager.threading.Thread', side_effect=immediate_thread), \
                patch('lyrics_manager.time.monotonic', return_value=100) as clock, \
                patch.object(self.manager, '_fetch_lyrics_open_orpheus', return_value=None) as fetch:
            self.manager.poll_status(bus)
            self.manager.poll_status(bus)
            self.assertEqual(fetch.call_count, 1)
            clock.return_value = 131
            self.manager.poll_status(bus)
            self.assertEqual(fetch.call_count, 2)

    def test_late_response_cannot_overwrite_new_track(self):
        def fetch(_):
            self.manager._fetch_id += 1
            self.manager.lyrics = [{'time_ms': 0, 'lyric': 'new'}]
            return [{'time_ms': 0, 'lyric': 'old'}]
        with patch.object(self.manager, '_fetch_lyrics_open_orpheus', side_effect=fetch):
            self.manager._fetch_lyrics('org.mpris.MediaPlayer2.open-orpheus',
                                       'Open Orpheus', track(), self.manager._fetch_id)
        self.assertEqual(self.manager.lyrics[0]['lyric'], 'new')


if __name__ == '__main__':
    unittest.main()
