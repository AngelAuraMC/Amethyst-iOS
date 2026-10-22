#!/usr/bin/env python3
"""Validate the launcher's English and Spanish catalogs on macOS."""

import collections
import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
ENTRY = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=', re.MULTILINE)
FORMAT = re.compile(
    r'%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?'
    r'(?:hh|ll|[hljztqL])?[@diuoxXfFeEgGaAcCsSp]'
)
REFERENCE = re.compile(r'(?:localize|NSLocalizedString)\s*\(\s*@"([^"\n]+)"')


def read_catalog(path, errors):
    # Comments cannot contain live entries; URLs inside values must be preserved.
    source = path.read_text()
    source = re.sub(r'^\s*//[^\n]*', '', source, flags=re.MULTILINE)
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.DOTALL)
    keys = [json.loads('"' + key + '"') for key in ENTRY.findall(source)]
    for key, count in collections.Counter(keys).items():
        if count > 1:
            errors.append(f'{path}: duplicate key {key}')
    catalog = json.loads(subprocess.check_output([
        'plutil', '-convert', 'json', '-o', '-', str(path)
    ]))
    for key, value in catalog.items():
        if not isinstance(value, str) or not value.strip():
            errors.append(f'{path}: empty or invalid value for {key}')
    return catalog


def main():
    resources = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'Natives/resources'
    errors = []
    catalogs = {}
    for table in ('Localizable', 'InfoPlist'):
        catalogs[table] = {
            lang: read_catalog(resources / f'{lang}.lproj/{table}.strings', errors)
            for lang in ('en', 'es')
        }
        en, es = catalogs[table]['en'], catalogs[table]['es']
        for lang, current, other in (('en', en, es), ('es', es, en)):
            for key in sorted(other.keys() - current.keys()):
                errors.append(f'{table}: missing {lang} translation for {key}')
        for key in en.keys() & es.keys():
            if FORMAT.findall(en[key]) != FORMAT.findall(es[key]):
                errors.append(f'{table}: incompatible format arguments for {key}')

    known = catalogs['Localizable']['en'].keys()
    for path in (ROOT / 'Natives').rglob('*.m'):
        if {'external', 'build'} & set(path.parts):
            continue
        for key in REFERENCE.findall(path.read_text()):
            if key not in known:
                errors.append(f'{path.relative_to(ROOT)}: missing literal key {key}')

    for key in ('NSLocalNetworkUsageDescription', 'NSMicrophoneUsageDescription'):
        if key not in catalogs['InfoPlist']['en']:
            errors.append(f'InfoPlist: missing permission description {key}')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'English and Spanish: {len(known)} app strings and '
          f'{len(catalogs["InfoPlist"]["en"])} permission descriptions verified; '
          'no missing keys, duplicates or incompatible format arguments.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
