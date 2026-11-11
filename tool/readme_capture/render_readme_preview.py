"""Render README.md to a GitHub-like HTML page for local preview.

Run from the repository root:

    python tool/readme_capture/render_readme_preview.py

Writes `docs/readme/_preview.html`. The file is a local preview only and is
not published with the documentation.
"""

from __future__ import annotations

import os

import markdown

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
README = os.path.join(ROOT, "README.md")
OUT = os.path.join(ROOT, "docs", "readme", "_preview.html")

STYLE = """
:root { color-scheme: light; }
body {
  margin: 0 auto; max-width: 1012px; padding: 32px 24px 96px;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
  font-size: 16px; line-height: 1.5; color: #1f2328; background: #ffffff;
}
.markdown-body { word-wrap: break-word; }
h1, h2, h3 { font-weight: 600; margin-top: 24px; margin-bottom: 16px; line-height: 1.25; }
h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid #d1d9e0; }
h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid #d1d9e0; }
h3 { font-size: 1.25em; }
p, ul, ol, table { margin-top: 0; margin-bottom: 16px; }
a { color: #0969da; text-decoration: none; }
a:hover { text-decoration: underline; }
code { background: #eff1f3; padding: .2em .4em; border-radius: 6px; font-size: 85%; }
hr { height: .25em; background: #d1d9e0; border: 0; margin: 24px 0; }
table { border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; }
th, td { padding: 6px 13px; border: 1px solid #d1d9e0; }
th { background: #f6f8fa; font-weight: 600; }
tr:nth-child(2n) td { background: #f6f8fa; }
img { max-width: 100%; }
div[align="center"] { text-align: center; }
sub { color: #59636e; font-size: 80%; }
"""


def main() -> None:
    with open(README, "r", encoding="utf-8") as handle:
        text = handle.read()

    # GitHub renders markdown inside a block level HTML element when the
    # content is separated by blank lines. python-markdown needs the same
    # effect spelled out, and the images have to resolve from the repository
    # root rather than from this file's folder.
    text = text.replace('<div align="center">', '<div align="center" markdown="1">')

    body = markdown.markdown(
        text,
        extensions=["extra", "tables", "sane_lists", "md_in_html"],
        output_format="html5",
    )

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write(
            "<!doctype html>\n<html lang=\"en\">\n<head>\n"
            "<meta charset=\"utf-8\" />\n"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n"
            "<base href=\"/\" />\n"
            "<title>Weekend README preview</title>\n"
            f"<style>{STYLE}</style>\n</head>\n<body class=\"markdown-body\">\n"
            f"{body}\n</body>\n</html>\n"
        )
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
