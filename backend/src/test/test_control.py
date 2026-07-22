import unittest

from server import LyricsServer


class ControlTest(unittest.TestCase):
    def test_like_action_reports_unsupported(self):
        result = LyricsServer()._execute_control("like", None)

        self.assertFalse(result["success"])
        self.assertEqual(result["action"], "like")
        self.assertIn("like/favorite", result["error"])


if __name__ == "__main__":
    unittest.main()
