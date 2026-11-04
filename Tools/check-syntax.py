"""Parse every Swift file with tree-sitter and report syntax errors.

    python Tools/check-syntax.py

No compiler is available on this machine, but a parser still catches the
syntax-level mistakes (a missing comma in a long argument list, an unbalanced
closure) that would otherwise surface as a wall of compiler errors on the Mac.
It says nothing about types.
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIRECTORIES = ["Swift", "App"]


def load_parser():
    try:
        from tree_sitter import Language, Parser
        import tree_sitter_swift
    except ImportError:
        print("tree-sitter-swift is not installed: uv pip install tree-sitter tree-sitter-swift")
        return None
    try:
        language = Language(tree_sitter_swift.language())
        return Parser(language)
    except TypeError:  # older bindings take the language in the constructor differently
        from tree_sitter import Parser as _Parser
        parser = _Parser()
        parser.set_language(Language(tree_sitter_swift.language()))
        return parser


def errors(node):
    stack = [node]
    while stack:
        current = stack.pop()
        if current.type == "ERROR" or getattr(current, "is_missing", False):
            yield current
        stack.extend(current.children)


def main() -> int:
    parser = load_parser()
    if parser is None:
        return 1

    files = []
    for directory in DIRECTORIES:
        files += sorted((ROOT / directory).rglob("*.swift"))

    failures = 0
    for path in files:
        source = path.read_bytes()
        tree = parser.parse(source)
        found = list(errors(tree.root_node))
        if not found:
            continue
        failures += 1
        relative = path.relative_to(ROOT)
        for node in sorted(found, key=lambda n: n.start_byte)[:5]:
            line, column = node.start_point
            snippet = source[node.start_byte:min(node.end_byte, node.start_byte + 60)]
            print(f"ERROR {relative}:{line + 1}:{column + 1}  {node.type}  {snippet!r}")

    print(f"{len(files)} files parsed, {failures} with syntax errors")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
