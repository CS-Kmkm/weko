#!/usr/bin/env python3

from pathlib import Path
import os
import sys

from jinja2 import Environment


def environ(name):
    value = os.environ.get(name)
    return "" if value is None else value


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: render_instance_cfg.py <template> <output>")

    template_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    rendered = Environment(autoescape=False).from_string(
        template_path.read_text(encoding="utf-8")
    ).render(environ=environ)

    if not rendered.strip():
        raise SystemExit("rendered instance config is empty")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = output_path.with_suffix(output_path.suffix + ".tmp")
    tmp_path.write_text(rendered, encoding="utf-8")
    tmp_path.replace(output_path)


if __name__ == "__main__":
    main()
