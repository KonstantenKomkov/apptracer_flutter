#!/usr/bin/env python3
"""Require external workflow actions to use immutable commits and version comments."""
from pathlib import Path
import re
import sys

import yaml
from yaml.nodes import MappingNode, ScalarNode, SequenceNode

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / '.github/workflows'
PIN = re.compile(r'[^@\s]+@[0-9a-fA-F]{40}')
# Upstream release names need not be numeric. Require a nonempty YAML comment.
COMMENT = r'[ \t]+#[ \t]*\S'


def fields(node, name=None):
    if isinstance(node, MappingNode):
        for key, value in node.value:
            if isinstance(key, ScalarNode) and (name is None or key.value.casefold() == name):
                yield key, value


def action_mappings(root):
    for _, jobs in fields(root, 'jobs'):
        for _, job in fields(jobs):
            yield job
            for _, steps in fields(job, 'steps'):
                if isinstance(steps, SequenceNode):
                    yield from steps.value


def trailing_comment(lines, mark):
    # Inline collections can close between the scalar and the comment.
    return bool(re.match(r'[ \t,}\]]*' + COMMENT, lines[mark.line][mark.column:]))


def has_version_comment(lines, block_headers, mapping, key, value):
    # A continuation or alias can have the version on the uses: line itself.
    end = key.end_mark
    if re.match(r'[ \t]*:[ \t]*(?:\*[^\s,}\]]+)?' + COMMENT,
                lines[end.line][end.column:]):
        return True
    if value.style in ('|', '>'):
        # The header can carry a comment. Hashes in the body are scalar data.
        start = block_headers[value.end_mark.index]
        return bool(re.search(COMMENT, lines[start.line][start.column:]))
    if mapping.flow_style and mapping.end_mark.line == value.end_mark.line:
        if trailing_comment(lines, mapping.end_mark):
            return True
    return trailing_comment(lines, value.end_mark)


def check_workflow(path):
    try:
        source = path.read_text(encoding='utf-8-sig')
        root = yaml.compose(source, Loader=yaml.BaseLoader)
        # A node can start at an anchor on a line before its block header.
        block_headers = {
            token.end_mark.index: token.start_mark
            for token in yaml.scan(source, Loader=yaml.BaseLoader)
            if isinstance(token, yaml.ScalarToken) and token.style in ('|', '>')
        }
    except yaml.MarkedYAMLError as error:
        return [f'{path}:{error.problem_mark.line + 1}: invalid YAML: {error.problem}']
    except (OSError, UnicodeError, yaml.YAMLError) as error:
        return [f'{path}: {error}']

    lines = source.splitlines() + ['']
    errors = []
    references = ((mapping, key, node) for mapping in action_mappings(root)
                  for key, node in fields(mapping, 'uses'))
    for mapping, key, node in references:
        location = f'{path}:{key.start_mark.line + 1}'
        if not isinstance(node, ScalarNode):
            errors.append(f'{location}: uses must be a scalar action reference')
        elif node.value.startswith('./'):
            continue
        elif not PIN.fullmatch(node.value):
            errors.append(
                f'{location}: external action must use a full 40-character commit SHA: {node.value!r}'
            )
        elif not has_version_comment(lines, block_headers, mapping, key, node):
            errors.append(f'{location}: {node.value} needs a version comment such as # v7')
    return errors


def check_workflows(directory=WORKFLOWS):
    paths = sorted(path for path in directory.rglob('*')
                   if path.suffix in ('.yml', '.yaml') and path.is_file())
    if not paths:
        return [], [f'{directory}: no .yml or .yaml workflow files found']
    return paths, [error for path in paths for error in check_workflow(path)]


def main():
    paths, errors = check_workflows(WORKFLOWS)
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'Checked external action pins in {len(paths)} workflow files.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
