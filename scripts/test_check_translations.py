#!/usr/bin/env python3
"""Self-test for scripts/check_translations.py.

Run with: python3 -I scripts/test_check_translations.py

Not wired into CI as a separate step (scripts/check-translations.sh already
exercises the real checker against the real strings files on every build);
this is a fast, standalone regression test for the checker's own logic,
run by a developer when touching check_translations.py.
"""
import sys
import os
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_translations as ct  # noqa: E402


class SpecifierMultisetTests(unittest.TestCase):
    def test_literal_percent_is_not_a_specifier(self):
        self.assertEqual(ct.specifier_multiset("100%%"), [])

    def test_mixed_real_specifier_and_literal_percent(self):
        # Exactly one real specifier -- %% must not be double-counted, and
        # must not force this (single-specifier) string into needing a
        # positional form.
        self.assertEqual(ct.specifier_multiset("Tilt %ld%%"), ["%ld"])
        self.assertEqual(ct.specifier_multiset("%.0f%% Humidity"), ["%.0f"])

    def test_positional_specifier_with_trailing_literal_percent(self):
        self.assertEqual(
            sorted(ct.specifier_multiset("%1$@ used %2$ld%% of capacity")),
            sorted(["%1$@", "%2$ld"]),
        )

    def test_two_real_specifiers_still_detected(self):
        self.assertEqual(
            sorted(ct.specifier_multiset("%1$@%2$@")),
            sorted(["%1$@", "%2$@"]),
        )

    def test_bare_percent_at_end_of_string_does_not_crash(self):
        # Malformed input (an unescaped trailing %) must not raise, and
        # must not be misread as a specifier.
        self.assertEqual(ct.specifier_multiset("100% done%"), [])


class PositionalRuleTests(unittest.TestCase):
    """Mirrors the positional-specifier check in main(): a string with 2+
    specifiers must use positional form; %% never counts towards that 2+."""

    def _violates_positional_rule(self, value):
        specs = ct.specifier_multiset(value)
        return len(specs) >= 2 and any(not ct.re.match(r"%\d+\$", s) for s in specs)

    def test_single_specifier_plus_literal_percent_is_fine_non_positional(self):
        self.assertFalse(self._violates_positional_rule("Tilt %ld%%"))
        self.assertFalse(self._violates_positional_rule("%.0f%% Humidity"))

    def test_two_real_specifiers_without_positional_form_is_flagged(self):
        self.assertTrue(self._violates_positional_rule("%@ %@"))

    def test_two_real_specifiers_with_positional_form_is_fine(self):
        self.assertFalse(self._violates_positional_rule("%1$@ %2$@"))


class PseudoLocalizeTests(unittest.TestCase):
    def test_literal_percent_passes_through_unchanged(self):
        result = ct.pseudo_localize("100%%")
        # The literal %% must survive untouched inside the brackets/padding.
        self.assertIn("100%%", result)

    def test_real_specifier_is_preserved_verbatim(self):
        result = ct.pseudo_localize("Tilt %ld%%")
        self.assertIn("%ld", result)
        self.assertIn("%%", result)


if __name__ == "__main__":
    unittest.main()
