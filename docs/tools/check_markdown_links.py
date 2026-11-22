#!/usr/bin/env python3
"""Validate repository-local destinations in tracked Markdown documents."""
import argparse
from functools import lru_cache
from html.parser import HTMLParser
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlsplit

from github_slugger import GithubSlugger
from markdown_it import MarkdownIt

ROOT = Path(__file__).resolve().parents[2]
MARKDOWN = MarkdownIt("commonmark").enable(["table", "strikethrough"])


class HTMLAnchors(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if value and (name == "id" or (tag == "a" and name == "name")):
                self.ids.add(value)


@lru_cache(maxsize=None)
def document(path):
    tokens = MARKDOWN.parse(path.read_text(encoding="utf-8"))
    anchors = HTMLAnchors()
    slugger = GithubSlugger()
    links = []
    for index, token in enumerate(tokens):
        if token.type == "html_block":
            anchors.feed(token.content)
        elif token.type == "inline":
            title = []
            for child in token.children:
                if child.type in {"text", "code_inline"}:
                    title.append(child.content)
                elif child.type == "html_inline":
                    anchors.feed(child.content)
                elif child.type in {"link_open", "image"}:
                    target = child.attrGet("href" if child.type == "link_open" else "src")
                    links.append((token.map[0] + 1, target))
            if index and tokens[index - 1].type == "heading_open":
                anchors.ids.add(slugger.slug("".join(title)))
    return links, anchors.ids


def check(root, files):
    errors = []
    for source in files:
        for line, target in document(source)[0]:
            url = urlsplit(target)
            if url.scheme or url.netloc:
                continue
            path = unquote(url.path)
            if path.startswith("/"):
                destination = root / path.lstrip("/")
            else:
                destination = source.parent / path if path else source
            destination = destination.resolve()
            if not destination.is_relative_to(root):
                reason = "link escapes repository"
            elif not destination.exists():
                reason = "missing target"
            else:
                if destination.is_dir():
                    destination = destination / "README.md"
                if not url.fragment or destination.suffix.lower() != ".md":
                    continue
                if destination.is_file() and unquote(url.fragment) in document(destination)[1]:
                    continue
                reason = "missing anchor"
            errors.append(f"{source.relative_to(root)}:{line}: {reason}: {target}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="paths relative to repo root")
    args = parser.parse_args()
    files = args.paths
    if not files:
        tracked = subprocess.check_output(["git", "ls-files", "-z", "--", "*.md"], cwd=ROOT)
        files = [Path(name.decode()) for name in tracked.split(b"\0") if name]
    errors = check(ROOT, [ROOT / path for path in files])
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Checked {len(files)} Markdown files")


if __name__ == "__main__":
    main()
