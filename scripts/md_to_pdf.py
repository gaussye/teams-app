"""
Convert READMENew.md to PDF using reportlab with Chinese font support.
Usage: python scripts/md_to_pdf.py
"""

import re
import os
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    HRFlowable, Preformatted, KeepTogether
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont

# ── Font registration (CJK Simplified Chinese) ──────────────────────────────
pdfmetrics.registerFont(UnicodeCIDFont('STSong-Light'))
FONT_NAME = 'STSong-Light'

# ── Styles ───────────────────────────────────────────────────────────────────
BASE = getSampleStyleSheet()

def style(name, parent='Normal', **kw):
    s = ParagraphStyle(name, parent=BASE[parent], fontName=FONT_NAME, **kw)
    return s

STYLES = {
    'h1': style('h1', 'Heading1', fontSize=20, spaceAfter=14, spaceBefore=20,
                textColor=colors.HexColor('#1a1a2e'), leading=26),
    'h2': style('h2', 'Heading2', fontSize=15, spaceAfter=8, spaceBefore=16,
                textColor=colors.HexColor('#16213e'), leading=20,
                borderPad=4),
    'h3': style('h3', 'Heading3', fontSize=12, spaceAfter=6, spaceBefore=12,
                textColor=colors.HexColor('#0f3460'), leading=16),
    'body': style('body', fontSize=10, spaceAfter=6, leading=16),
    'bullet': style('bullet', fontSize=10, spaceAfter=4, leading=15,
                    leftIndent=16, bulletIndent=6),
    'bullet2': style('bullet2', fontSize=10, spaceAfter=4, leading=15,
                     leftIndent=32, bulletIndent=22),
    'blockquote': style('blockquote', fontSize=10, spaceAfter=6, leading=15,
                        leftIndent=20, textColor=colors.HexColor('#555555'),
                        backColor=colors.HexColor('#f5f5f5')),
    'code_inline': style('code_inline', fontSize=9, fontName='Courier',
                         textColor=colors.HexColor('#c7254e')),
    'caption': style('caption', fontSize=9, spaceAfter=4, leading=13,
                     textColor=colors.HexColor('#666666'), alignment=1),
    'table_header': style('table_header', fontSize=9, leading=13,
                          textColor=colors.white),
    'table_cell': style('table_cell', fontSize=9, leading=13),
}

def escape_xml(text):
    """Escape characters that break reportlab XML parsing."""
    return (text
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;'))

def inline_format(text):
    """Convert inline Markdown (bold, italic, code) to reportlab XML."""
    text = escape_xml(text)
    # Bold+italic
    text = re.sub(r'\*\*\*(.+?)\*\*\*', r'<b><i>\1</i></b>', text)
    # Bold
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    # Italic
    text = re.sub(r'\*(.+?)\*', r'<i>\1</i>', text)
    # Inline code
    text = re.sub(r'`([^`]+)`',
                  r'<font name="Courier" color="#c7254e">\1</font>', text)
    # Links → just show text
    text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'<b>\1</b>', text)
    return text

# ── Main parser ───────────────────────────────────────────────────────────────

def parse_table(lines):
    """Parse a Markdown table block into a reportlab Table."""
    rows = []
    for line in lines:
        if re.match(r'^[\|\s\-:]+$', line.strip()):
            continue  # separator row
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        rows.append(cells)
    if not rows:
        return None

    header = rows[0]
    data_rows = rows[1:]

    # Header row
    header_data = [Paragraph(f'<b>{inline_format(c)}</b>', STYLES['table_cell'])
                   for c in header]
    table_data = [header_data]
    for row in data_rows:
        table_data.append(
            [Paragraph(inline_format(c), STYLES['table_cell']) for c in row]
        )

    col_count = len(header)
    usable_width = 16 * cm
    col_width = usable_width / col_count

    tbl = Table(table_data, colWidths=[col_width] * col_count,
                repeatRows=1)
    tbl.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#16213e')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('FONTNAME', (0, 0), (-1, -1), FONT_NAME),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1),
         [colors.HexColor('#f8f8f8'), colors.white]),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#cccccc')),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
    ]))
    return tbl


def md_to_elements(md_text):
    """Convert Markdown text to a list of reportlab flowables."""
    elements = []
    lines = md_text.splitlines()
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]

        # ── Horizontal rule ──────────────────────────────────────────────────
        if re.match(r'^---+$', line.strip()):
            elements.append(Spacer(1, 4))
            elements.append(HRFlowable(width='100%', thickness=1,
                                        color=colors.HexColor('#cccccc')))
            elements.append(Spacer(1, 4))
            i += 1
            continue

        # ── Fenced code block ────────────────────────────────────────────────
        if line.strip().startswith('```'):
            lang = line.strip()[3:].strip()
            code_lines = []
            i += 1
            while i < n and not lines[i].strip().startswith('```'):
                code_lines.append(lines[i])
                i += 1
            i += 1  # skip closing ```
            code_text = '\n'.join(code_lines)
            label = f'[{lang} code]' if lang else '[code]'
            if lang.lower() == 'mermaid':
                label = '[Mermaid diagram – render in VS Code with Markdown Preview Mermaid Support]'
            elements.append(Spacer(1, 4))
            code_style = ParagraphStyle(
                'code_block', fontName='Courier', fontSize=8,
                backColor=colors.HexColor('#f4f4f4'),
                textColor=colors.HexColor('#333333'),
                borderColor=colors.HexColor('#dddddd'),
                borderWidth=1, borderPad=6,
                spaceAfter=8, leading=12
            )
            if lang.lower() == 'mermaid':
                elements.append(Paragraph(
                    f'<i>{escape_xml(label)}</i>', STYLES['caption']))
                elements.append(Preformatted(code_text, code_style))
            else:
                elements.append(Preformatted(code_text, code_style))
            continue

        # ── Headings ─────────────────────────────────────────────────────────
        m = re.match(r'^(#{1,3})\s+(.*)', line)
        if m:
            level = len(m.group(1))
            text = inline_format(m.group(2))
            key = f'h{level}' if level <= 3 else 'h3'
            elements.append(Paragraph(text, STYLES[key]))
            i += 1
            continue

        # ── Table ─────────────────────────────────────────────────────────────
        if '|' in line and line.strip().startswith('|'):
            table_lines = []
            while i < n and '|' in lines[i]:
                table_lines.append(lines[i])
                i += 1
            tbl = parse_table(table_lines)
            if tbl:
                elements.append(Spacer(1, 4))
                elements.append(tbl)
                elements.append(Spacer(1, 8))
            continue

        # ── Blockquote ────────────────────────────────────────────────────────
        if line.startswith('>'):
            text = inline_format(line.lstrip('> ').strip())
            elements.append(Paragraph(text, STYLES['blockquote']))
            i += 1
            continue

        # ── Unordered list ────────────────────────────────────────────────────
        m = re.match(r'^(\s*)[-*+]\s+(.*)', line)
        if m:
            indent = len(m.group(1))
            text = inline_format(m.group(2))
            bullet_style = STYLES['bullet2'] if indent >= 2 else STYLES['bullet']
            elements.append(Paragraph(f'• {text}', bullet_style))
            i += 1
            continue

        # ── Ordered list ──────────────────────────────────────────────────────
        m = re.match(r'^(\s*)\d+\.\s+(.*)', line)
        if m:
            indent = len(m.group(1))
            text = inline_format(m.group(2))
            bullet_style = STYLES['bullet2'] if indent >= 2 else STYLES['bullet']
            elements.append(Paragraph(text, bullet_style))
            i += 1
            continue

        # ── Empty line ────────────────────────────────────────────────────────
        if not line.strip():
            elements.append(Spacer(1, 4))
            i += 1
            continue

        # ── Normal paragraph ──────────────────────────────────────────────────
        text = inline_format(line.strip())
        if text:
            elements.append(Paragraph(text, STYLES['body']))
        i += 1

    return elements


def convert(md_path, pdf_path):
    with open(md_path, encoding='utf-8') as f:
        md_text = f.read()

    doc = SimpleDocTemplate(
        pdf_path,
        pagesize=A4,
        leftMargin=2.2 * cm,
        rightMargin=2.2 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
        title='Teams App 对接 Custom Agent 方案总结',
        author='Teams Agent Documentation',
    )

    elements = md_to_elements(md_text)
    doc.build(elements)
    print(f'PDF saved: {pdf_path}')


if __name__ == '__main__':
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    md_file = os.path.join(base, 'READMENew.md')
    pdf_file = os.path.join(base, 'READMENew.pdf')
    convert(md_file, pdf_file)
