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
import io
import contextlib
import tempfile
import shutil
import plistlib
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_translations as ct  # noqa: E402


def build_project(tmp_dir, langs, source_files=None):
    """langs: {"en": {"key": "value", ...}, "fr": {...}} -> writes
    HADashboard/<lang>.lproj/Localizable.strings for each. source_files is
    an optional {relative_path_under_HADashboard: file_content} map, for
    tests that need a HALocalizedString call site.
    """
    ha_dir = os.path.join(tmp_dir, "HADashboard")
    os.makedirs(ha_dir, exist_ok=True)
    for lang, entries in langs.items():
        lproj = os.path.join(ha_dir, f"{lang}.lproj")
        os.makedirs(lproj, exist_ok=True)
        with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-8") as f:
            for k, v in entries.items():
                f.write(f'"{k}" = "{v}";\n')
    if source_files:
        for relpath, content in source_files.items():
            full = os.path.join(ha_dir, relpath)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w", encoding="utf-8") as f:
                f.write(content)


def run_checker(tmp_dir, strict=False, pseudo=False):
    argv = ["check_translations.py", tmp_dir]
    if strict:
        argv.append("--strict")
    if pseudo:
        argv.append("--pseudo")
    old_argv = sys.argv
    sys.argv = argv
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            status = ct.main()
    finally:
        sys.argv = old_argv
    return status, buf.getvalue()


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


class StrictModeFixtureTests(unittest.TestCase):
    """Self-tests for the maintainer's "a language must never be merged
    partially" requirement: isolated temp project trees (never the real
    HADashboard/*.lproj content), exercising check_translations.main()
    end to end in both modes.
    """

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="i18n-strict-test-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_partial_language_missing_key_fails_only_in_strict(self):
        build_project(self.tmp, {"en": {"a": "A", "b": "B"}, "fr": {"a": "Ah"}})

        strict_status, strict_out = run_checker(self.tmp, strict=True)
        self.assertNotEqual(strict_status, 0, strict_out)
        self.assertIn("missing", strict_out.lower())
        self.assertIn("--strict", strict_out)

        lenient_status, lenient_out = run_checker(self.tmp, strict=False)
        self.assertEqual(lenient_status, 0, lenient_out)
        self.assertIn("missing", lenient_out.lower())  # still reported, just as a warning

    def test_empty_value_fails_only_in_strict(self):
        build_project(self.tmp, {"en": {"a": "A"}, "fr": {"a": "   "}})

        strict_status, strict_out = run_checker(self.tmp, strict=True)
        self.assertNotEqual(strict_status, 0, strict_out)
        self.assertIn("empty", strict_out.lower())

        lenient_status, _lenient_out = run_checker(self.tmp, strict=False)
        self.assertEqual(lenient_status, 0)

    def test_extra_key_fails_in_both_modes(self):
        build_project(self.tmp, {"en": {"a": "A"}, "fr": {"a": "Ah", "b": "Bee"}})

        for strict in (False, True):
            status, out = run_checker(self.tmp, strict=strict)
            self.assertNotEqual(status, 0, f"strict={strict}: {out}")
            self.assertIn("not present in en.lproj", out)

    def test_format_specifier_mismatch_fails_in_both_modes(self):
        build_project(self.tmp, {"en": {"a": "Hello %@"}, "fr": {"a": "Bonjour %ld"}})

        for strict in (False, True):
            status, out = run_checker(self.tmp, strict=strict)
            self.assertNotEqual(status, 0, f"strict={strict}: {out}")
            self.assertIn("format-specifier mismatch", out)

    def test_complete_language_passes_in_strict(self):
        build_project(self.tmp, {"en": {"a": "A", "b": "B"}, "fr": {"a": "Ah", "b": "Bee"}})
        status, out = run_checker(self.tmp, strict=True)
        self.assertEqual(status, 0, out)

    def test_identical_to_english_values_are_warning_only(self):
        # "OK" is a realistic legitimately-identical value across en/fr.
        build_project(self.tmp, {"en": {"a": "OK", "b": "B"}, "fr": {"a": "OK", "b": "Bee"}})
        status, out = run_checker(self.tmp, strict=True)
        self.assertEqual(status, 0, out)
        self.assertIn("identical", out.lower())
        self.assertIn("(1 unallowlisted)", out)

    def test_allowlist_suppresses_identical_value_from_unallowlisted_count(self):
        build_project(self.tmp, {"en": {"a": "OK"}, "fr": {"a": "OK"}})
        allowlist_path = os.path.join(self.tmp, "HADashboard", "fr.lproj", ".i18n-identical-allowlist")
        with open(allowlist_path, "w", encoding="utf-8") as f:
            f.write("# intentionally identical\na\n")

        status, out = run_checker(self.tmp, strict=True)
        self.assertEqual(status, 0, out)
        self.assertIn("(0 unallowlisted)", out)

    def test_malformed_strings_syntax_fails_in_both_modes(self):
        # Missing semicolon -- STRINGS_LINE_RE won't match this entry at
        # all, so it survives comment/entry stripping and is flagged.
        build_project(self.tmp, {"en": {"a": "A"}})
        bad_path = os.path.join(self.tmp, "HADashboard", "fr.lproj")
        os.makedirs(bad_path, exist_ok=True)
        with open(os.path.join(bad_path, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write('"a" = "Ah"\n')  # no trailing semicolon

        for strict in (False, True):
            status, out = run_checker(self.tmp, strict=strict)
            self.assertNotEqual(status, 0, f"strict={strict}: {out}")
            self.assertIn("unparseable", out)

    def test_stringsdict_missing_plural_category_fails_only_in_strict(self):
        build_project(self.tmp, {"en": {"a": "A"}, "fr": {"a": "Ah"}})

        en_dict = {
            "count": {
                "NSStringLocalizedFormatKey": "%#@items@",
                "items": {
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "d",
                    "one": "%d item",
                    "other": "%d items",
                },
            }
        }
        # French needs one/many/other (REQUIRED_PLURAL_CATEGORIES) -- this
        # fixture only provides "other", missing "one" and "many".
        fr_dict = {
            "count": {
                "NSStringLocalizedFormatKey": "%#@items@",
                "items": {
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "d",
                    "other": "%d articles",
                },
            }
        }
        with open(os.path.join(self.tmp, "HADashboard", "en.lproj", "Localizable.stringsdict"), "wb") as f:
            plistlib.dump(en_dict, f)
        with open(os.path.join(self.tmp, "HADashboard", "fr.lproj", "Localizable.stringsdict"), "wb") as f:
            plistlib.dump(fr_dict, f)

        strict_status, strict_out = run_checker(self.tmp, strict=True)
        self.assertNotEqual(strict_status, 0, strict_out)
        self.assertIn("plural categor", strict_out.lower())

        lenient_status, lenient_out = run_checker(self.tmp, strict=False)
        self.assertEqual(lenient_status, 0, lenient_out)
        self.assertIn("plural categor", lenient_out.lower())  # still reported, just as a warning

    def test_stringsdict_complete_plural_categories_passes_strict(self):
        build_project(self.tmp, {"en": {"a": "A"}, "fr": {"a": "Ah"}})

        shape = {
            "count": {
                "NSStringLocalizedFormatKey": "%#@items@",
                "items": {
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "d",
                    "one": "%d item",
                    "other": "%d items",
                },
            }
        }
        fr_shape = {
            "count": {
                "NSStringLocalizedFormatKey": "%#@items@",
                "items": {
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "d",
                    "one": "%d article",
                    "many": "%d articles",
                    "other": "%d articles",
                },
            }
        }
        with open(os.path.join(self.tmp, "HADashboard", "en.lproj", "Localizable.stringsdict"), "wb") as f:
            plistlib.dump(shape, f)
        with open(os.path.join(self.tmp, "HADashboard", "fr.lproj", "Localizable.stringsdict"), "wb") as f:
            plistlib.dump(fr_shape, f)

        status, out = run_checker(self.tmp, strict=True)
        self.assertEqual(status, 0, out)

    def test_invalid_stringsdict_plist_fails_in_both_modes(self):
        build_project(self.tmp, {"en": {"a": "A"}, "fr": {"a": "Ah"}})
        with open(os.path.join(self.tmp, "HADashboard", "en.lproj", "Localizable.stringsdict"), "wb") as f:
            f.write(b"not a plist at all")
        with open(os.path.join(self.tmp, "HADashboard", "fr.lproj", "Localizable.stringsdict"), "wb") as f:
            f.write(b"<plist><dict></dict></plist>")  # also not valid XML plist (no version/doctype)

        for strict in (False, True):
            status, out = run_checker(self.tmp, strict=strict)
            self.assertNotEqual(status, 0, f"strict={strict}: {out}")
            self.assertIn("invalid plist", out)

    def test_stringsdict_missing_entirely_fails_only_in_strict(self):
        build_project(self.tmp, {"en": {"a": "A"}, "fr": {"a": "Ah"}})
        shape = {"count": {"NSStringLocalizedFormatKey": "%#@items@",
                            "items": {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                                      "NSStringFormatValueTypeKey": "d",
                                      "one": "%d item", "other": "%d items"}}}
        with open(os.path.join(self.tmp, "HADashboard", "en.lproj", "Localizable.stringsdict"), "wb") as f:
            plistlib.dump(shape, f)
        # fr.lproj deliberately gets no Localizable.stringsdict at all.

        strict_status, strict_out = run_checker(self.tmp, strict=True)
        self.assertNotEqual(strict_status, 0, strict_out)
        self.assertIn("missing Localizable.stringsdict", strict_out)

        lenient_status, lenient_out = run_checker(self.tmp, strict=False)
        self.assertEqual(lenient_status, 0, lenient_out)
        self.assertIn("missing Localizable.stringsdict", lenient_out)


if __name__ == "__main__":
    unittest.main()
