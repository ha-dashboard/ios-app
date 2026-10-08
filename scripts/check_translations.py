#!/usr/bin/env python3
"""Validate HADashboard/<lang>.lproj/Localizable.strings against en.lproj.

Run via scripts/check-translations.sh, not directly (it needs -I to avoid
loading anything from the current/script directory -- see repo CLAUDE.md
untrusted-input handling note, which this inherits as a defensive default).
"""
import argparse
import os
import re
import sys
import glob

STRINGS_LINE_RE = re.compile(
    r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.MULTILINE
)
# %@, %1$@, %ld, %2$ld, %.2f, %1$.2f, %%, etc.
SPECIFIER_RE = re.compile(
    r'%(\d+\$)?[-+0 #]*\d*(\.\d+)?(hh|h|ll|l|q|L|z|j|t)?[@diufsuxXoc%]'
)
CALL_SITE_RE = re.compile(r'HALocalizedString\(\s*@"((?:[^"\\]|\\.)*)"')
PLURAL_CALL_SITE_RE = re.compile(r'HALocalizedPlural\(\s*@"((?:[^"\\]|\\.)*)"')


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("project_dir")
    parser.add_argument("--pseudo", action="store_true")
    args = parser.parse_args()

    project_dir = args.project_dir
    lproj_dirs = find_lproj_dirs(project_dir)
    en_dir = os.path.join(project_dir, "HADashboard", "en.lproj")
    en_strings_path = os.path.join(en_dir, "Localizable.strings")

    if not os.path.isfile(en_strings_path):
        print(f"❌ {en_strings_path} not found", file=sys.stderr)
        return 1

    status = 0

    try:
        en_entries = parse_strings_file(en_strings_path)
    except ValueError as e:
        print(f"❌ {e}", file=sys.stderr)
        return 1

    print(f"en.lproj: {len(en_entries)} keys")

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

    for lang_dir in other_dirs:
        lang = os.path.basename(lang_dir).replace(".lproj", "")
        strings_path = os.path.join(lang_dir, "Localizable.strings")
        if not os.path.isfile(strings_path):
            continue
        try:
            lang_entries = parse_strings_file(strings_path)
        except ValueError as e:
            status = 1
            print(f"❌ {e}")
            continue

        extra = sorted(k for k in lang_entries if k not in en_entries)
        missing = sorted(k for k in en_entries if k not in lang_entries)

        if extra:
            status = 1
            print(f"❌ {lang}.lproj has {len(extra)} key(s) not present in en.lproj (typo'd/dead key):")
            for k in extra:
                print(f"   - {k}")
        if missing:
            print(f"⚠️  {lang}.lproj is missing {len(missing)} key(s) present in en.lproj (falls back to en):")
            for k in missing:
                print(f"   - {k}")

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

        print(f"{lang}.lproj: {len(lang_entries)} keys, {len(missing)} missing, {len(extra)} extra")

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
