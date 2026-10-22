import subprocess
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

SCRIPT = Path(__file__).resolve().parents[1] / 'update-appcast.py'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


class ReleaseNotesTests(unittest.TestCase):
    def test_embedded_notes_preserve_signature_and_replace_existing_version(self):
        with tempfile.TemporaryDirectory() as directory:
            feed = Path(directory) / 'feed.xml'
            feed.write_text('<rss><channel/></rss>')
            notes = Path(directory) / 'notes.txt'
            notes.write_text('Detect app failures.\nKeep A & B settings.')
            command = ['python3', str(SCRIPT), '--appcast', str(feed), '--version',
                       '1.1.17', '--build', '76', '--url', 'https://example.com/app.dmg',
                       '--length', '123', '--signature', 'signed',
                       '--release-notes-file', str(notes)]
            for _ in range(2):
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            items = ET.parse(feed).findall('channel/item')
            self.assertEqual(len(items), 1)
            item = items[0]
            self.assertIsNone(item.find(f'{{{SPARKLE}}}releaseNotesLink'))
            self.assertEqual(item.findtext('description'), notes.read_text())
            self.assertEqual(item.find('description').get(f'{{{SPARKLE}}}format'), 'plain-text')
            self.assertEqual(item.find('enclosure').get(f'{{{SPARKLE}}}edSignature'), 'signed')
            self.assertEqual(item.find('enclosure').get('length'), '123')

    def test_notes_source_is_unambiguous(self):
        result = subprocess.run(['python3', str(SCRIPT), '--appcast', 'unused',
                                 '--version', '1', '--build', '1', '--url', 'https://example.com',
                                 '--length', '1', '--signature', 'signed',
                                 '--release-notes-file', 'unused', '--release-notes-url',
                                 'https://example.com/notes'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('not allowed with argument', result.stderr)


if __name__ == '__main__':
    unittest.main()
