#!/usr/bin/env python3
"""
Aggressive .rej hunk applier with adaptive context shrinking.

Each hunk has context lines (' ' prefix) and change lines ('-' / '+').
The ideal apply uses ALL context, but if the surrounding code shifted
between versions (e.g. function signatures changed), full match fails.
This tool tries progressively SHORTER context windows around the change
until it finds a unique match in the target file.

Usage: python3 apply_rejs.py <openjdk-source-root>
"""
import os, re, sys
from pathlib import Path

HUNK_HEADER = re.compile(r'^@@ ', re.MULTILINE)

def parse_hunks(rej_text):
    """Yield list of (kind, content) tuples per hunk. kind is '-', '+', or ' '."""
    # Strip the first 'diff a/... b/...' line if present
    parts = re.split(r'^@@.*?@@.*$', rej_text, flags=re.MULTILINE)
    for body in parts[1:]:
        hunk = []
        for line in body.split('\n'):
            if not line:
                hunk.append((' ', ''))
                continue
            if line[0] in ('-', '+', ' '):
                # Skip --- / +++ headers (shouldn't occur in body but safe)
                if line.startswith('---') or line.startswith('+++'):
                    continue
                hunk.append((line[0], line[1:]))
            elif line.startswith('\\'):
                # `\ No newline at end of file` markers — ignore
                continue
            # else: unknown line, skip
        # Trim trailing blank-context lines that often arrive from rej format
        while hunk and hunk[-1] == (' ', ''):
            hunk.pop()
        while hunk and hunk[0] == (' ', ''):
            hunk.pop(0)
        if hunk:
            yield hunk

def try_apply_hunk(text, hunk):
    """
    Apply hunk to text. Try progressively shorter context windows.
    Returns (new_text, status) where status is 'ok', 'ambiguous',
    'no_match', or 'no_change'.
    """
    # Find boundary of change region (-/+ lines)
    first_change = None
    last_change = None
    for i, (k, _) in enumerate(hunk):
        if k != ' ':
            if first_change is None:
                first_change = i
            last_change = i
    if first_change is None:
        return text, 'no_change'

    n = len(hunk)
    # Try each (leading_context_count, trailing_context_count) shrink from
    # ALL the way down to 0+0. Outer iterations first try with more context.
    max_lead = first_change            # lines 0..first_change-1
    max_trail = n - 1 - last_change    # lines last_change+1..n-1

    # Strategy: walk shrinking from full down to none, but always prefer
    # MORE context (less aggressive shrinking) before LESS.
    attempts = []
    for ld in range(max_lead, -1, -1):
        for tr in range(max_trail, -1, -1):
            attempts.append((ld, tr))

    last_ambiguous = None
    for ld, tr in attempts:
        window = hunk[max_lead - ld : last_change + 1 + tr]
        old_lines = [c for k, c in window if k != '+']
        new_lines = [c for k, c in window if k != '-']
        if not old_lines:
            continue
        old_str = '\n'.join(old_lines)
        new_str = '\n'.join(new_lines)
        # Avoid trivial case where old==new (pure addition with no - lines)
        if old_str == new_str and not any(k == '+' for k, _ in window):
            continue
        count = text.count(old_str)
        if count == 1:
            new_text = text.replace(old_str, new_str, 1)
            return new_text, f'ok (lead={ld} trail={tr})'
        elif count > 1:
            last_ambiguous = (ld, tr, count)

    if last_ambiguous:
        return text, f'ambiguous ({last_ambiguous[2]}× at lead={last_ambiguous[0]} trail={last_ambiguous[1]})'
    return text, 'no_match'


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
    rejs = sorted(root.rglob('*.rej'))
    if not rejs:
        print(f"[apply_rejs] no .rej files under {root}")
        return 0
    total_applied, total_failed = 0, 0
    for rej in rejs:
        target = Path(str(rej)[:-4])  # strip .rej suffix
        if not target.exists():
            print(f"[apply_rejs] WARN target missing: {target}")
            continue
        try:
            rel = target.relative_to(root) if target.is_absolute() else target
        except ValueError:
            rel = target
        text = target.read_text()
        hunks = list(parse_hunks(rej.read_text()))
        applied = 0
        details = []
        for i, hunk in enumerate(hunks, 1):
            text, status = try_apply_hunk(text, hunk)
            if status.startswith('ok'):
                applied += 1
            details.append((i, status))
        if applied:
            target.write_text(text)
        ok_count = sum(1 for _, s in details if s.startswith('ok'))
        fail_count = len(details) - ok_count
        total_applied += ok_count
        total_failed += fail_count
        sym = 'ok' if fail_count == 0 else 'partial' if ok_count else 'fail'
        print(f"[apply_rejs] {sym:7} {rel}: {ok_count}/{len(hunks)}")
        for i, status in details:
            if not status.startswith('ok'):
                print(f"           hunk {i}: {status}")
        if fail_count == 0:
            rej.unlink()
    print(f"[apply_rejs] TOTAL: {total_applied} applied, {total_failed} still failing")
    return 0

if __name__ == '__main__':
    sys.exit(main())
