#!/usr/bin/env python3
"""merge-words.py merges one-line lists by word and leaves every real conflict to git's line merge."""
from pathlib import Path
import subprocess
import tempfile
import unittest

DRIVER = Path(__file__).with_name('merge-words.py')
LIST = 'A="one two"\nB="x"\n'


class MergeWordsTests(unittest.TestCase):
    def merge(self, base, ours, theirs):
        """(exit code, what the driver left in ours)."""
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for name, text in (('base', base), ('ours', ours), ('theirs', theirs)):
                paths.append(Path(directory, name))
                paths[-1].write_bytes(text.encode())
            result = subprocess.run(['python3', str(DRIVER), *map(str, paths)], capture_output=True, text=True)
            return result.returncode, paths[1].read_bytes().decode()

    def test_both_sides_append_to_one_list(self):
        self.assertEqual(self.merge(LIST, 'A="one two ours-test"\nB="x"\n', 'A="one two theirs-test"\nB="x"\n'),
                         (0, 'A="one two ours-test theirs-test"\nB="x"\n'))

    def test_additions_at_different_places_of_one_line(self):
        self.assertEqual(self.merge('| a | F1 One | F2 Two |\n', '| a | F1 One, F3 Three | F2 Two |\n',
                                    '| a | F1 One | F2 Two, F4 Four |\n'),
                         (0, '| a | F1 One, F3 Three | F2 Two, F4 Four |\n'))

    def test_both_sides_add_to_one_table_cell(self):
        self.assertEqual(self.merge('| a | F1 One |\n', '| a | F1 One, F3 Three |\n', '| a | F1 One, F4 Four |\n'),
                         (0, '| a | F1 One, F3 Three, F4 Four |\n'))

    def test_one_side_moves_a_name_the_other_adds_one(self):
        self.assertEqual(self.merge('| a | F1 One | F2 Two, F9 Nine |\n', '| a | F1 One, F9 Nine | F2 Two |\n',
                                    '| a | F1 One, F4 Four | F2 Two, F9 Nine |\n'),
                         (0, '| a | F1 One, F9 Nine, F4 Four | F2 Two |\n'))

    def test_the_same_addition_on_both_sides_lands_once(self):
        self.assertEqual(self.merge(LIST, 'A="one two new"\nB="x"\n', 'A="one two new"\nB="x"\n'),
                         (0, 'A="one two new"\nB="x"\n'))

    def test_one_name_added_by_both_sides_among_others_conflicts(self):
        code, text = self.merge(LIST, 'A="one two new ours-test"\nB="x"\n', 'A="one two new theirs-test"\nB="x"\n')
        self.assertEqual(code, 1)
        self.assertIn('A="one two new ours-test"\n=======\nA="one two new theirs-test"\n', text)

    def test_a_removed_name_stays_removed(self):
        self.assertEqual(self.merge('A="one two three"\n', 'A="one three"\n', 'A="one two three four"\n'),
                         (0, 'A="one three four"\n'))
        self.assertEqual(self.merge('A="one two three"\n', 'A="one two three four"\n', 'A="one three"\n'),
                         (0, 'A="one three four"\n'))

    def test_a_name_removed_beside_an_addition_conflicts(self):
        code, text = self.merge('A="one two"\n', 'A="one"\n', 'A="one two three"\n')
        self.assertEqual(code, 1)
        self.assertIn('A="one"\n=======\nA="one two three"\n', text)

    def test_one_word_changed_on_both_sides_conflicts(self):
        code, text = self.merge('SIZE=6\nA="one"\n', 'SIZE=7\nA="one"\n', 'SIZE=8\nA="one"\n')
        self.assertEqual(code, 1)
        self.assertIn('<<<<<<<', text)
        self.assertIn('SIZE=7\n=======\nSIZE=8\n', text)

    def test_lines_both_sides_add_at_one_place_conflict(self):
        code, text = self.merge(LIST, LIST + 'C="1"\n', LIST + 'C="2"\n')
        self.assertEqual(code, 1)
        self.assertIn('C="1"\n=======\nC="2"\n', text)

    def test_changes_on_different_lines_merge_as_before(self):
        self.assertEqual(self.merge(LIST, 'A="one"\nB="x"\n', 'A="one two"\nB="y"\n'), (0, 'A="one"\nB="y"\n'))

    def test_spacing_and_line_endings_survive(self):
        self.assertEqual(self.merge('A="one"\r\n\tB="x"  \n', 'A="one two"\r\n\tB="x"  \n', 'A="one"\r\n\tB="x y"  \n'),
                         (0, 'A="one two"\r\n\tB="x y"  \n'))

    def test_bytes_that_are_not_text_get_the_line_merge(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory, name) for name in ('base', 'ours', 'theirs')]
            for path, data in zip(paths, (b'\xff one\n', b'\xff one\ntwo\n', b'zero\n\xff one\n')):
                path.write_bytes(data)
            result = subprocess.run(['python3', str(DRIVER), *map(str, paths)], capture_output=True)
            self.assertEqual((result.returncode, paths[1].read_bytes()), (0, b'zero\n\xff one\ntwo\n'))


if __name__ == '__main__':
    unittest.main()
