#!/usr/bin/env python3
"""Validate HADashboard/<lang>.lproj/Localizable.strings against en.lproj.

Run via scripts/check-translations.sh, not directly (it needs -I to avoid
loading anything from the current/script directory -- see repo CLAUDE.md
untrusted-input handling note, which this inherits as a defensive default).

Two modes:

- Default (lenient): the mode this script always ran in. Missing keys in a
  non-en language are a WARNING only (a partial translation still falls
  back to English at runtime, so it is not by itself broken). Extra keys,
  format-specifier mismatches, bad encoding, and invalid plist/strings
  syntax are always hard failures, in both modes -- these are correctness
  bugs, not incompleteness.
- `--strict` (CI's mode, see .github/workflows/translations.yml): a
  language must be MERGED COMPLETE, never partial. Strict mode additionally
  fails on: any key missing vs en, any empty/whitespace-only value, and any
  .stringsdict plural-category gap. Values identical to English are never
  a failure in either mode -- they are collected into a warning summary
  instead, since some strings (e.g. "OK", "HA") are legitimately identical
  across languages. A per-language allowlist file can silence specific
  keys from that warning summary; see `load_identical_allowlist`.
"""
import argparse
import os
import plistlib
import re
import sys
import glob

STRINGS_LINE_RE = re.compile(
    r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.MULTILINE
)
COMMENT_RE = re.compile(r'/\*.*?\*/', re.DOTALL)
# %@, %1$@, %ld, %2$ld, %.2f, %1$.2f, %%, etc.
# NOTE: '%%' (a literal percent sign, not a conversion) is intentionally NOT
# matched here. It must never count as a specifier, and must never trigger
# the positional-specifier requirement -- "Tilt %ld%%" has exactly one real
# specifier (%ld) and is perfectly fine non-positional.
SPECIFIER_RE = re.compile(
    r'%(\d+\$)?[-+0#]*\d*(\.\d+)?(hh|h|ll|l|q|L|z|j|t)?[@diufsuxXc]'
)
CALL_SITE_RE = re.compile(r'HALocalizedString\(\s*@"((?:[^"\\]|\\.)*)"')
PLURAL_CALL_SITE_RE = re.compile(r'HALocalizedPlural\(\s*@"((?:[^"\\]|\\.)*)"')

# Minimum CLDR plural categories a translation of a given language is
# expected to provide in a .stringsdict NSStringVariableType dict. This is
# NOT a full CLDR table -- it only covers languages this project has
# concretely discussed (plan docs/plans/i18n-plan.md §4.2: French needs
# one/many/other, and treats 0 as singular, which is "one" in CLDR's
# french rule, not a separate category). Anything not listed falls back to
# the universally-required ["other"], which will under-report for
# languages that need more -- extend this table when a new language's
# requirements are known, rather than guessing.
REQUIRED_PLURAL_CATEGORIES = {
    "en": {"one", "other"},
    "fr": {"one", "many", "other"},
}
DEFAULT_REQUIRED_PLURAL_CATEGORIES = {"other"}


def read_text_strict(path):
    """Read a .strings file, rejecting UTF-16/BOM encodings explicitly."""
    with open(path, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        raise ValueError(f"{path}: UTF-16 BOM detected -- must be UTF-8, no BOM")
    if raw.startswith(b"\xef\xbb\xbf"):
        raise ValueError(f"{path}: UTF-8 BOM detected -- strip it")
    # A real UTF-16 file with no BOM will contain many NUL bytes.
    if b"\x00" in raw[:200]:
        raise ValueError(f"{path}: looks like UTF-16 (NUL bytes) -- must be UTF-8")
    return raw.decode("utf-8")


def parse_strings_file(path):
    text = read_text_strict(path)
    entries = {}
    for m in STRINGS_LINE_RE.finditer(text):
        key, value = m.group(1), m.group(2)
        entries[key] = value
    return entries


def validate_strings_syntax(path):
    """Cross-platform stand-in for `plutil -lint` on an OpenStep-format
    .strings SOURCE file (not yet compiled to a binary plist, so Python's
    plistlib -- which only reads XML/binary plists -- cannot parse it
    directly). Strips /* ... */ comments and every well-formed "key" =
    "value"; entry; anything left over (a missing semicolon, an unescaped
    quote, a stray fragment) is a syntax error. Returns a list of error
    strings (empty = valid).
    """
    try:
        raw = read_text_strict(path)
    except ValueError as e:
        return [str(e)]
    stripped = COMMENT_RE.sub('', raw)
    remainder = STRINGS_LINE_RE.sub('', stripped)
    remainder = remainder.strip()
    if remainder:
        snippet = remainder[:80].replace("\n", "\\n")
        return [f"{path}: unparseable content outside comments and \"key\" = \"value\"; entries: {snippet!r}"]
    return []


def validate_stringsdict_plist(path):
    """.stringsdict IS a real XML plist, so plistlib can parse it directly
    -- this is the cross-platform equivalent of `plutil -lint` for it."""
    try:
        with open(path, "rb") as f:
            plistlib.load(f)
        return []
    except Exception as e:
        return [f"{path}: invalid plist ({e})"]


def specifier_multiset(value):
    specs = []
    for m in SPECIFIER_RE.finditer(value):
        specs.append(m.group(0))
    return sorted(specs)


def find_lproj_dirs(project_dir):
    pattern = os.path.join(project_dir, "HADashboard", "*.lproj")
    return sorted(d for d in glob.glob(pattern) if os.path.isdir(d))


def find_call_site_keys(project_dir):
    keys = set()
    plural_keys = set()
    src_root = os.path.join(project_dir, "HADashboard")
    for dirpath, _dirnames, filenames in os.walk(src_root):
        for name in filenames:
            if not (name.endswith(".m") or name.endswith(".h")):
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    text = f.read()
            except OSError:
                continue
            for m in CALL_SITE_RE.finditer(text):
                keys.add(m.group(1))
            for m in PLURAL_CALL_SITE_RE.finditer(text):
                plural_keys.add(m.group(1))
    return keys, plural_keys


def load_identical_allowlist(lang_dir):
    """Optional `.i18n-identical-allowlist` file inside a <lang>.lproj
    directory: one key per line, blank lines and `#`-comments ignored.
    Keys listed here are expected to be legitimately identical to English
    (e.g. "OK", "HA", a brand name) and are excluded from the
    identical-value warning summary. Never affects pass/fail -- identical
    values are only ever a warning.
    """
    path = os.path.join(lang_dir, ".i18n-identical-allowlist")
    if not os.path.isfile(path):
        return set()
    allowed = set()
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                allowed.add(line)
    return allowed


PSEUDO_MAP = {
    "a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú",
    "A": "Á", "E": "É", "I": "Í", "O": "Ó", "U": "Ú",
    "n": "ñ", "N": "Ñ", "c": "ç", "s": "š",
}


def pseudo_localize(value):
    out = []
    i = 0
    while i < len(value):
        ch = value[i]
        if ch == "%":
            # Copy the whole format specifier untouched.
            m = SPECIFIER_RE.match(value, i)
            if m:
                out.append(m.group(0))
                i = m.end()
                continue
        out.append(PSEUDO_MAP.get(ch, ch))
        i += 1
    base = "".join(out)
    pad = max(1, len(base) * 2 // 5)
    return f"[{base}{'~' * pad}]"


def check_stringsdict_parity(en_dir, lang_dir, lang, strict):
    """Returns (status_delta, messages). Only runs when en.lproj actually
    ships a Localizable.stringsdict -- this repo has none yet (no plural
    strings extracted so far), so this is forward-looking plumbing for
    when one lands.
    """
    status = 0
    messages = []
    en_dict_path = os.path.join(en_dir, "Localizable.stringsdict")
    if not os.path.isfile(en_dict_path):
        return status, messages

    lang_dict_path = os.path.join(lang_dir, "Localizable.stringsdict")
    if not os.path.isfile(lang_dict_path):
        msg = f"{'❌' if strict else '⚠️ '} {lang}.lproj is missing Localizable.stringsdict (en.lproj has one)"
        messages.append(msg)
        if strict:
            status = 1
        return status, messages

    en_errors = validate_stringsdict_plist(en_dict_path)
    lang_errors = validate_stringsdict_plist(lang_dict_path)
    for e in en_errors + lang_errors:
        messages.append(f"❌ {e}")
        status = 1
    if en_errors or lang_errors:
        return status, messages

    with open(en_dict_path, "rb") as f:
        en_dict = plistlib.load(f)
    with open(lang_dict_path, "rb") as f:
        lang_dict = plistlib.load(f)

    required = REQUIRED_PLURAL_CATEGORIES.get(lang, DEFAULT_REQUIRED_PLURAL_CATEGORIES)

    missing_keys = sorted(k for k in en_dict if k not in lang_dict)
    if missing_keys:
        tag = "❌" if strict else "⚠️ "
        messages.append(f"{tag} {lang}.lproj Localizable.stringsdict is missing {len(missing_keys)} key(s): {missing_keys}")
        if strict:
            status = 1

    for key, en_entry in en_dict.items():
        lang_entry = lang_dict.get(key)
        if not isinstance(lang_entry, dict) or not isinstance(en_entry, dict):
            continue
        for var_name, var_rules in en_entry.items():
            if not isinstance(var_rules, dict):
                continue  # e.g. NSStringLocalizedFormatKey, a plain string
            lang_var_rules = lang_entry.get(var_name)
            if not isinstance(lang_var_rules, dict):
                messages.append(f"❌ {lang}.lproj stringsdict key '{key}': missing plural variable '{var_name}'")
                status = 1
                continue
            present_categories = {k for k in lang_var_rules.keys() if k != "NSStringFormatSpecTypeKey" and k != "NSStringFormatValueTypeKey"}
            missing_categories = required - present_categories
            if missing_categories:
                tag = "❌" if strict else "⚠️ "
                messages.append(
                    f"{tag} {lang}.lproj stringsdict key '{key}' variable '{var_name}' is missing "
                    f"required plural categor{'y' if len(missing_categories) == 1 else 'ies'} for '{lang}': "
                    f"{sorted(missing_categories)}"
                )
                if strict:
                    status = 1

    return status, messages


def check_language(lang_dir, en_entries, en_dir, strict):
    """Returns (status_delta, identical_count, identical_flagged)."""
    status = 0
    lang = os.path.basename(lang_dir).replace(".lproj", "")
    strings_path = os.path.join(lang_dir, "Localizable.strings")
    if not os.path.isfile(strings_path):
        return status, 0, 0

    syntax_errors = validate_strings_syntax(strings_path)
    for e in syntax_errors:
        print(f"❌ {e}")
        status = 1
    if syntax_errors:
        return status, 0, 0

    try:
        lang_entries = parse_strings_file(strings_path)
    except ValueError as e:
        print(f"❌ {e}")
        return 1, 0, 0

    extra = sorted(k for k in lang_entries if k not in en_entries)
    missing = sorted(k for k in en_entries if k not in lang_entries)

    if extra:
        status = 1
        print(f"❌ {lang}.lproj has {len(extra)} key(s) not present in en.lproj (typo'd/dead key):")
        for k in extra:
            print(f"   - {k}")

    if missing:
        if strict:
            status = 1
            print(f"❌ {lang}.lproj is missing {len(missing)} key(s) present in en.lproj -- a partial "
                  f"translation cannot be merged (--strict). Fix: add each key below to "
                  f"{strings_path}, with the English text from en.lproj as a starting point:")
        else:
            print(f"⚠️  {lang}.lproj is missing {len(missing)} key(s) present in en.lproj (falls back to en):")
        for k in missing:
            print(f"   - {k}")

    empty_values = sorted(k for k, v in lang_entries.items() if k in en_entries and v.strip() == "")
    if empty_values:
        tag = "❌" if strict else "⚠️ "
        print(f"{tag} {lang}.lproj has {len(empty_values)} key(s) with an empty/whitespace-only value "
              f"(--strict treats this as missing):")
        for k in empty_values:
            print(f"   - {k}")
        if strict:
            status = 1

    for key, en_value in en_entries.items():
        if key not in lang_entries:
            continue
        en_specs = specifier_multiset(en_value)
        lang_specs = specifier_multiset(lang_entries[key])
        if en_specs != lang_specs:
            status = 1
            print(
                f"❌ format-specifier mismatch for '{key}': "
                f"en={en_specs} {lang}={lang_specs}"
            )

    allowlist = load_identical_allowlist(lang_dir)
    identical_keys = sorted(
        k for k, v in lang_entries.items()
        if k in en_entries and v == en_entries[k] and v.strip() != ""
    )
    identical_flagged = [k for k in identical_keys if k not in allowlist]
    if identical_flagged:
        print(f"ℹ️  {lang}.lproj: {len(identical_flagged)} key(s) have the same value as en "
              f"(not a failure -- flag with a {lang}.lproj/.i18n-identical-allowlist entry if intentional):")
        for k in identical_flagged:
            print(f"   - {k}")

    dict_status, dict_messages = check_stringsdict_parity(en_dir, lang_dir, lang, strict)
    for m in dict_messages:
        print(m)
    status = status or dict_status

    print(f"{lang}.lproj: {len(lang_entries)} keys, {len(missing)} missing, {len(extra)} extra, "
          f"{len(identical_keys)} identical-to-en ({len(identical_flagged)} unallowlisted)")

    return status, len(identical_keys), len(identical_flagged)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("project_dir")
    parser.add_argument("--pseudo", action="store_true")
    parser.add_argument("--strict", action="store_true",
                         help="Fail on missing keys, empty values, and .stringsdict plural gaps "
                              "(not just extra keys / specifier mismatches, which always fail). "
                              "This is CI's mode (.github/workflows/translations.yml) -- a language "
                              "must be merged complete, never partial.")
    args = parser.parse_args()

    project_dir = args.project_dir
    lproj_dirs = find_lproj_dirs(project_dir)
    en_dir = os.path.join(project_dir, "HADashboard", "en.lproj")
    en_strings_path = os.path.join(en_dir, "Localizable.strings")

    if not os.path.isfile(en_strings_path):
        print(f"❌ {en_strings_path} not found", file=sys.stderr)
        return 1

    status = 0

    en_syntax_errors = validate_strings_syntax(en_strings_path)
    for e in en_syntax_errors:
        print(f"❌ {e}", file=sys.stderr)
    if en_syntax_errors:
        return 1

    try:
        en_entries = parse_strings_file(en_strings_path)
    except ValueError as e:
        print(f"❌ {e}", file=sys.stderr)
        return 1

    print(f"en.lproj: {len(en_entries)} keys" + (" [--strict]" if args.strict else ""))

    call_keys, plural_keys = find_call_site_keys(project_dir)
    missing_from_en = sorted(k for k in call_keys if k not in en_entries)
    if missing_from_en:
        status = 1
        print(f"❌ {len(missing_from_en)} HALocalizedString key(s) used in source but absent from en.lproj:")
        for k in missing_from_en:
            print(f"   - {k}")

    unused_in_en = sorted(k for k in en_entries if k not in call_keys and k not in plural_keys)
    if unused_in_en:
        print(f"⚠️  {len(unused_in_en)} en.lproj key(s) not referenced by any HALocalizedString call site (dead string):")
        for k in unused_in_en:
            print(f"   - {k}")

    # Format-specifier parity, 2+ specifiers must use positional form.
    for key, value in en_entries.items():
        specs = specifier_multiset(value)
        if len(specs) >= 2:
            if any(not re.match(r"%\d+\$", s) for s in specs):
                status = 1
                print(f"❌ en.lproj key '{key}' has {len(specs)} specifiers but is not fully positional: {value!r}")

    other_dirs = [d for d in lproj_dirs if os.path.basename(d) not in ("en.lproj", "Base.lproj")]

    total_identical = 0
    total_identical_flagged = 0
    for lang_dir in other_dirs:
        lang_status, identical_count, identical_flagged = check_language(lang_dir, en_entries, en_dir, args.strict)
        status = status or lang_status
        total_identical += identical_count
        total_identical_flagged += identical_flagged

    if other_dirs:
        print(f"\nSummary: {len(other_dirs)} non-en language(s) checked, "
              f"{total_identical} total identical-to-en value(s) ({total_identical_flagged} unallowlisted)")

    if args.pseudo:
        pseudo_dir = os.path.join(project_dir, "HADashboard", "en-XA.lproj")
        os.makedirs(pseudo_dir, exist_ok=True)
        out_path = os.path.join(pseudo_dir, "Localizable.strings")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write("/* Generated by scripts/check-translations.sh --pseudo. Git-ignored. */\n")
            for key, value in sorted(en_entries.items()):
                pseudo_value = pseudo_localize(value)
                escaped = pseudo_value.replace('"', '\\"')
                f.write(f'"{key}" = "{escaped}";\n')
        print(f"Wrote pseudo-localisation: {out_path}")

    if status == 0:
        print("\n✅ Translation checks passed")
    else:
        print("\n❌ Translation checks failed")
    return status


if __name__ == "__main__":
    sys.exit(main())
