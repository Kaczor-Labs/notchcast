#!/usr/bin/env python3
"""merge-words.py merges one-line lists by word and leaves every real conflict to git's line merge."""
from pathlib import Path
import subprocess
import tempfile
import unittest

DRIVER = Path(__file__).with_name('merge-words.py')
LIST = 'A_TESTS="one two"\nB="x"\n'


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
        self.assertEqual(self.merge(LIST, 'A_TESTS="one two ours-test"\nB="x"\n', 'A_TESTS="one two theirs-test"\nB="x"\n'),
                         (0, 'A_TESTS="one two ours-test theirs-test"\nB="x"\n'))

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
        self.assertEqual(self.merge(LIST, 'A_TESTS="one two new"\nB="x"\n', 'A_TESTS="one two new"\nB="x"\n'),
                         (0, 'A_TESTS="one two new"\nB="x"\n'))

    def test_a_name_both_sides_added_beside_others_lands_once(self):
        self.assertEqual(self.merge('A_TESTS="a d"\n', 'A_TESTS="a b c d"\n', 'A_TESTS="a b d"\n'), (0, 'A_TESTS="a b c d"\n'))
        self.assertEqual(self.merge('A_TESTS="a d"\n', 'A_TESTS="a b c d"\n', 'A_TESTS="a c d"\n'), (0, 'A_TESTS="a b c d"\n'))
        self.assertEqual(self.merge('A_TESTS="a d"\n', 'A_TESTS="a x b d"\n', 'A_TESTS="a b y d"\n'), (0, 'A_TESTS="a x b y d"\n'))
        self.assertEqual(self.merge('A_TESTS="a"\n', 'A_TESTS="a x b"\n', 'A_TESTS="a b y"\n'), (0, 'A_TESTS="a x b y"\n'))

    def test_an_entry_both_sides_added_to_one_table_cell_lands_once(self):
        self.assertEqual(self.merge('| a | F1 One |\n', '| a | F1 One, F3 Three, F4 Four |\n',
                                    '| a | F1 One, F4 Four |\n'),
                         (0, '| a | F1 One, F3 Three, F4 Four |\n'))

    def test_entries_sharing_a_word_both_land(self):
        self.assertEqual(self.merge('| a | F1 One |\n', '| a | F1 One, F3 New |\n', '| a | F1 One, F4 New |\n'),
                         (0, '| a | F1 One, F3 New, F4 New |\n'))

    def test_a_name_both_sides_added_at_different_places_lands_once(self):
        self.assertEqual(self.merge('A_TESTS="a c"\n', 'A_TESTS="a b c"\n', 'A_TESTS="a c b"\n'), (0, 'A_TESTS="a b c"\n'))
        self.assertEqual(self.merge('A_TESTS="x, z"\n', 'A_TESTS="x, y, z"\n', 'A_TESTS="x, z, y"\n'), (0, 'A_TESTS="x, y, z"\n'))

    def test_sentences_both_sides_append_to_one_paragraph_stay_whole(self):
        self.assertEqual(self.merge('Run the check.\n', 'Run the check. Run the suite before a push to main.\n',
                                    'Run the check. Never run the suite on a Mac host.\n'),
                         (0, 'Run the check. Run the suite before a push to main. Never run the suite on a Mac host.\n'))
        self.assertEqual(self.merge('Run it.\n', 'Run it. A draft, as the card says, runs no build.\n',
                                    'Run it. A worker, as the card says, opens a draft.\n'),
                         (0, 'Run it. A draft, as the card says, runs no build. A worker, as the card says, opens a draft.\n'))

    def test_columns_both_sides_add_to_one_table_stay_aligned(self):
        base = '| a | b |\n|---|---|\n| 1 | 2 |\n'
        ours = '| a | X | Z | b |\n|---|---|---|---|\n| 1 | yes | no | 2 |\n'
        theirs = '| a | Y | b |\n|---|---|---|\n| 1 | yes | 2 |\n'
        code, text = self.merge(base, ours, theirs)
        self.assertEqual(code, 0)
        self.assertEqual([row.count('|') for row in text.splitlines()], [6, 6, 6])

    def test_a_quoted_value_with_a_comma_stays_whole(self):
        self.assertEqual(self.merge('A="x"\n', 'A="x" B="1,2" C="1,3"\n', 'A="x" B="1,2" D="1,3"\n'),
                         (0, 'A="x" B="1,2" C="1,3" B="1,2" D="1,3"\n'))

    def test_entries_holding_brackets_or_code_stay_whole(self):
        self.assertEqual(self.merge('| a | F1 One |\n', '| a | F1 One, F3 Three (beta) |\n',
                                    '| a | F1 One, F4 Four (beta) |\n'),
                         (0, '| a | F1 One, F3 Three (beta), F4 Four (beta) |\n'))
        self.assertEqual(self.merge('| a | `f(a, b)` |\n', '| a | `f(a, b)`, `g(a, b)` |\n',
                                    '| a | `f(a, b)`, `h(a, b)` |\n'),
                         (0, '| a | `f(a, b)`, `g(a, b)`, `h(a, b)` |\n'))
        self.assertEqual(self.merge('L_TESTS="a d"\n', 'L_TESTS="a b(1) d"\n', 'L_TESTS="a c(1) d"\n'),
                         (0, 'L_TESTS="a b(1) c(1) d"\n'))

    def test_a_quoted_value_that_is_not_a_name_list_keeps_both_sides(self):
        value = 'Xcode 27.2 Build version 27B52 ProductName: macOS ProductVersion: 27.2.1 BuildVersion: 26B131'
        self.assertEqual(self.merge(f'ISOLATED_TOOLCHAIN="{value}"\n',
                                    f'ISOLATED_TOOLCHAIN="{value.replace("Xcode 27.2", "Xcode 27.3")}"\n',
                                    f'ISOLATED_TOOLCHAIN="{value.replace("ProductVersion: 27.2.1", "ProductVersion: 27.3")}"\n'),
                         (0, 'ISOLATED_TOOLCHAIN="Xcode 27.3 Build version 27B52 ProductName: macOS ProductVersion: 27.3 '
                             'BuildVersion: 26B131"\n'))
        self.assertEqual(self.merge('OLD_APP="/Applications/Tinycast Beta.app"\n',
                                    'OLD_APP="/Applications/Old /Applications/Tinycast Beta.app"\n',
                                    'OLD_APP="/Applications/Other /Applications/Tinycast Beta.app"\n'),
                         (0, 'OLD_APP="/Applications/Old /Applications/Other /Applications/Tinycast Beta.app"\n'))
        self.assertEqual(self.merge('ARGS="-n 1"\n', 'ARGS="-n 1 -m 1"\n', 'ARGS="-n 1 -k 1"\n'),
                         (0, 'ARGS="-n 1 -m 1 -k 1"\n'))

    def test_a_removed_name_stays_removed(self):
        self.assertEqual(self.merge('A_TESTS="one two three"\n', 'A_TESTS="one three"\n', 'A_TESTS="one two three four"\n'),
                         (0, 'A_TESTS="one three four"\n'))
        self.assertEqual(self.merge('A_TESTS="a b d"\n', 'A_TESTS="a c d"\n', 'A_TESTS="a c d e"\n'), (0, 'A_TESTS="a c d e"\n'))
        self.assertEqual(self.merge('A_TESTS="one two three"\n', 'A_TESTS="one two three four"\n', 'A_TESTS="one three"\n'),
                         (0, 'A_TESTS="one three four"\n'))

    def test_a_name_removed_beside_an_addition_conflicts(self):
        code, text = self.merge('A_TESTS="one two"\n', 'A_TESTS="one"\n', 'A_TESTS="one two three"\n')
        self.assertEqual(code, 1)
        self.assertIn('A_TESTS="one"\n=======\nA_TESTS="one two three"\n', text)

    def test_one_word_changed_on_both_sides_conflicts(self):
        code, text = self.merge('SIZE=6\nA_TESTS="one"\n', 'SIZE=7\nA_TESTS="one"\n', 'SIZE=8\nA_TESTS="one"\n')
        self.assertEqual(code, 1)
        self.assertIn('<<<<<<<', text)
        self.assertIn('SIZE=7\n=======\nSIZE=8\n', text)

    def test_lines_both_sides_add_at_one_place_conflict(self):
        code, text = self.merge(LIST, LIST + 'C="1"\n', LIST + 'C="2"\n')
        self.assertEqual(code, 1)
        self.assertIn('C="1"\n=======\nC="2"\n', text)

    def test_changes_on_different_lines_merge_as_before(self):
        self.assertEqual(self.merge(LIST, 'A_TESTS="one"\nB="x"\n', 'A_TESTS="one two"\nB="y"\n'), (0, 'A_TESTS="one"\nB="y"\n'))

    def test_spacing_and_line_endings_survive(self):
        self.assertEqual(self.merge('A_TESTS="one"\r\n\tB="x"  \n', 'A_TESTS="one two"\r\n\tB="x"  \n', 'A_TESTS="one"\r\n\tB="x y"  \n'),
                         (0, 'A_TESTS="one two"\r\n\tB="x y"  \n'))

    def test_bytes_that_are_not_text_get_the_line_merge(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory, name) for name in ('base', 'ours', 'theirs')]
            for path, data in zip(paths, (b'\xff one\n', b'\xff one\ntwo\n', b'zero\n\xff one\n')):
                path.write_bytes(data)
            result = subprocess.run(['python3', str(DRIVER), *map(str, paths)], capture_output=True)
            self.assertEqual((result.returncode, paths[1].read_bytes()), (0, b'zero\n\xff one\ntwo\n'))


if __name__ == '__main__':
    unittest.main()
