#!/usr/bin/env python3
"""Add `public` to Swift declarations at indent 0 and indent 4 only."""
import re
import sys
import os

ACCESS_MODIFIERS = {'private', 'fileprivate', 'internal', 'public', 'open'}
TYPE_KEYWORDS = {'struct', 'class', 'enum', 'actor', 'protocol'}
MEMBER_KEYWORDS = {'func', 'init', 'subscript', 'typealias', 'let', 'var'}


def get_keyword(stripped):
    words = stripped.split()
    pure_modifiers = {'nonisolated', 'static', 'override', 'final',
                      'lazy', 'weak', 'unowned', 'mutating', 'nonmutating',
                      'required', 'convenience', 'optional', 'sending'}
    for idx, word in enumerate(words):
        if word in pure_modifiers:
            continue
        if word == 'class':
            next_word = words[idx + 1] if idx + 1 < len(words) else ''
            if next_word in ('func', 'var', 'subscript', 'let'):
                continue
            return 'class'
        return word
    return None


def has_access(stripped):
    for mod in ACCESS_MODIFIERS:
        if stripped.startswith(mod + ' ') or stripped.startswith(mod + '('):
            return True
    return False


def process_file(filepath):
    with open(filepath, 'r') as fobj:
        lines = fobj.readlines()

    result = []
    modified = False
    current_indent0_type = None

    for line in lines:
        rstripped = line.rstrip('\n')
        stripped = rstripped.strip()
        indent = len(rstripped) - len(rstripped.lstrip()) if stripped else 0

        # Track indent-0 type context
        if indent == 0 and stripped:
            skip_prefixes = ('//', '@', 'import', '#', '}', '/*', '*')
            if not any(stripped.startswith(p) for p in skip_prefixes):
                kw = get_keyword(stripped)
                if kw == 'protocol':
                    current_indent0_type = 'protocol'
                elif kw in TYPE_KEYWORDS or kw == 'extension':
                    current_indent0_type = 'type'
            if stripped == '}':
                current_indent0_type = None

        should_add = False

        if stripped and not has_access(stripped):
            # Skip comments, attributes, imports, preprocessor, control flow
            skip = ('//', '/*', '*', '@', '#', 'import ', 'case ')
            if not any(stripped.startswith(s) for s in skip):
                kw = get_keyword(stripped)

                if indent == 0:
                    if kw in TYPE_KEYWORDS:
                        should_add = True
                    elif kw in ('func', 'typealias'):
                        should_add = True

                elif indent == 4 and current_indent0_type == 'type':
                    if kw in TYPE_KEYWORDS or kw in MEMBER_KEYWORDS:
                        should_add = True

        if should_add:
            leading = rstripped[:indent]
            rest = rstripped[indent:]
            result.append(leading + 'public ' + rest + '\n')
            modified = True
        else:
            result.append(line)

    if modified:
        with open(filepath, 'w') as fobj:
            fobj.writelines(result)
    return modified


def add_sendable_to_enums(filepath):
    with open(filepath, 'r') as fobj:
        content = fobj.read()
    pattern = r'(public enum \w+\s*:\s*[^{]+?)(\s*\{)'
    def add_sendable(match):
        decl = match.group(1)
        brace = match.group(2)
        if 'Sendable' not in decl:
            return decl.rstrip() + ', Sendable' + brace
        return match.group(0)
    new_content = re.sub(pattern, add_sendable, content)
    if new_content != content:
        with open(filepath, 'w') as fobj:
            fobj.write(new_content)
        return True
    return False


def main():
    base_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    pub = send = total = 0
    for root, _, files in os.walk(base_dir):
        for fname in sorted(files):
            if fname.endswith('.swift') and fname != 'CoreExports.swift':
                fpath = os.path.join(root, fname)
                total += 1
                if process_file(fpath):
                    pub += 1
                if add_sendable_to_enums(fpath):
                    send += 1
    print(f"Processed {total}, public: {pub}, sendable: {send}")


if __name__ == '__main__':
    main()
