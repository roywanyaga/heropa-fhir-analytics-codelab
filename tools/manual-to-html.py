#!/usr/bin/env python3
"""Turns course-manual.md into HTML to paste into a Heropa course.

Heropa's editor keeps inline styles and drops classes and stylesheets, so
every style is written on the element itself. The output goes to heropa-html,
as one whole page and as one file for each numbered section.

Run it from the repository root after every change to the manual.

    python3 tools/manual-to-html.py

It needs the markdown-it-py package, which Ubuntu ships as
python3-markdown-it.
"""

import base64
import html
import pathlib
import re
import shutil
import sys

from markdown_it import MarkdownIt

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "course-manual.md"
OUT = ROOT / "heropa-html"

TABLE = "border-collapse: collapse; width: 100%; margin-bottom: 16px;"
TH = "border: 1px solid #333; padding: 8px; text-align: left; background: #f5f5f5;"
TD = "border: 1px solid #333; padding: 8px;"
PRE = "background: #f6f8fa; border: 1px solid #ddd; padding: 12px; overflow-x: auto; white-space: pre;"
# Heropa's own stylesheet lets text inside code wrap, which joins the lines of
# a block into one. Saying it again on the code element keeps the line breaks.
CODE = "white-space: pre; font-family: monospace;"
IMG = "max-width: 100%; height: auto; border: 1px solid #ddd;"
NOTE = "border-left: 4px solid #4a90d9; background: #eef5fc; padding: 8px 12px;"
WARN = "border-left: 4px solid #e0a800; background: #fff8e1; padding: 8px 12px;"
DONE = "border-left: 4px solid #2e7d32; background: #e8f5e9; padding: 8px 12px;"

# Paragraphs that open with one of these bold sentences get the amber style,
# because a learner who misses them goes wrong. Any other paragraph that opens
# with a bold sentence gets the blue one.
WARNINGS = ("The addresses and password in this manual are examples only.",)


def plain(fragment):
    """The text of an HTML fragment, without tags or entities."""
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


def convert(markdown):
    page = MarkdownIt("commonmark", {"html": False}).enable("table").render(markdown)

    # Headings are bold already, and Heropa numbers nothing by itself, so the
    # text stays as written.
    titles = set()
    for match in re.finditer(r"<h[1-6]>(.*?)</h[1-6]>", page):
        title = plain(match.group(1))
        titles.add(title)
        titles.add(re.sub(r"^\d+\.\s+", "", title))

    # A paragraph that is one bold line and nothing else is a small heading.
    page = re.sub(r"<p><strong>((?:(?!</strong>).)*)</strong></p>", r"<h4>\1</h4>", page)

    # A paragraph that opens with a bold sentence is a callout.
    def callout(match):
        lead = plain(match.group(1))
        style = WARN if lead in WARNINGS else NOTE
        return f'<p style="{style}"><strong>{match.group(1)}</strong> '

    page = re.sub(r"<p><strong>((?:(?!</strong>).)*\.)</strong> ", callout, page)

    # The first paragraph of the closing section is the one green callout.
    page = re.sub(
        r"(<h2>[^<]*Congratulations[^<]*</h2>\s*)<p>",
        rf'\1<p style="{DONE}">',
        page,
    )

    # Bold marks things to click. The name of another section is a reference,
    # which goes in italics.
    def reference(match):
        if plain(match.group(1)) in titles:
            return f"<em>{match.group(1)}</em>"
        return match.group(0)

    page = re.sub(r"<strong>((?:(?!</strong>).)*)</strong>", reference, page)

    page = page.replace("<table>", f'<table style="{TABLE}">')
    page = re.sub(r"<th(?: style=\"[^\"]*\")?>", f'<th style="{TH}">', page)
    page = re.sub(r"<td(?: style=\"[^\"]*\")?>", f'<td style="{TD}">', page)
    page = re.sub(r"<pre><code(?: class=\"[^\"]*\")?>", f'<pre style="{PRE}"><code style="{CODE}">', page)
    # The diagrams are SVG files that sit in guide-images. Heropa has no place to
    # host them, so each one is written into the page as a data address.
    def diagram(match):
        name = pathlib.Path(match.group(1)).name
        data = base64.b64encode((ROOT / "guide-images" / name).read_bytes()).decode()
        return f'<img src="data:image/svg+xml;base64,{data}" {match.group(2)}'

    page = re.sub(r'<img src="images/([^"]+)" ([^>]*?)(?= ?/?>)', diagram, page)
    page = re.sub(r"<img ([^>]*?) ?/?>", rf'<img \1 style="{IMG}" />', page)
    return page


def slug(title):
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def main():
    page = convert(SOURCE.read_text(encoding="utf-8"))

    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "sections").mkdir(parents=True)
    (OUT / "course-manual.html").write_text(page, encoding="utf-8")

    # One file for each part that starts at a second level heading. The part
    # before the first one holds the title and the introduction.
    parts = re.split(r"(?=<h2>)", page)
    for number, part in enumerate(parts):
        heading = re.match(r"<h2>(.*?)</h2>", part)
        title = plain(heading.group(1)) if heading else "introduction"
        title = re.sub(r"^\d+\.\s+", "", title)
        name = f"{number:02d}-{slug(title)}.html"
        (OUT / "sections" / name).write_text(part.strip() + "\n", encoding="utf-8")
        print(f"  sections/{name}")

    print(f"Wrote {OUT.relative_to(ROOT)}/course-manual.html and {len(parts)} sections")


if __name__ == "__main__":
    sys.exit(main())
