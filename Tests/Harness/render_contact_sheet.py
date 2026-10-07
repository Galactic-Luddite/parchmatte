#!/usr/bin/env python3
import base64
import csv
import html
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("usage: render_contact_sheet.py CSV TEXTURE_DIR OUTPUT.svg")

csv_path, texture_dir, output_path = map(Path, sys.argv[1:])
with csv_path.open(newline="") as handle:
    rows = list(csv.DictReader(handle))

chosen = {}
for row in rows:
    key = (row["texture"], row["strength"])
    if row["softness_step"] == "10" and row["scale"] == "2" and row["lamp"] == "lateNight" and row["glow"] == "medium":
        chosen[key] = row

textures = ["linen", "vellum"]
strengths = [("low", "0.15"), ("mid", "0.3"), ("max", "0.6")]
columns = [("current", "Current"), ("candidate", "Candidate")]
card_w, card_h, gap = 250, 128, 14
margin, label_w = 24, 92
width = margin * 2 + label_w + 4 * (card_w + gap)
height = 78 + 6 * (card_h + gap) + 34

defs = []
for texture in textures:
    encoded = base64.b64encode((texture_dir / f"{texture}.png").read_bytes()).decode()
    defs.append(f'<pattern id="{texture}" width="128" height="128" patternUnits="userSpaceOnUse"><image href="data:image/png;base64,{encoded}" width="128" height="128"/></pattern>')
defs.append('<radialGradient id="lamp"><stop offset="0" stop-color="#f2731f" stop-opacity="1"/><stop offset="1" stop-color="#f2731f" stop-opacity="0.55"/></radialGradient>')

parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
         '<defs>' + ''.join(defs) + '</defs>',
         '<rect width="100%" height="100%" fill="#202124"/>',
         '<text x="24" y="30" fill="#fff" font-family="-apple-system,sans-serif" font-size="20" font-weight="700">Parchmatte render budget: current vs candidate</text>',
         '<text x="24" y="54" fill="#b9bdc6" font-family="-apple-system,sans-serif" font-size="13">Synthetic light/dark text and swatches; Late Night / Medium, softness 50%, scale 2</text>']

for theme_index, theme in enumerate(["light", "dark"]):
    for mode_index, (_, mode_title) in enumerate(columns):
        column_index = theme_index * 2 + mode_index
        x = margin + label_w + column_index * (card_w + gap)
        parts.append(f'<text x="{x}" y="76" fill="#ddd" font-family="-apple-system,sans-serif" font-size="12">{mode_title} · {theme}</text>')

display_names = {"linen": "Woven", "vellum": "Soft Leaf"}
for texture_index, texture in enumerate(textures):
    for strength_index, (strength_label, strength) in enumerate(strengths):
        row_index = texture_index * 3 + strength_index
        y = 84 + row_index * (card_h + gap)
        parts.append(f'<text x="24" y="{y + 20}" fill="#ddd" font-family="-apple-system,sans-serif" font-size="13">{html.escape(display_names[texture])}</text>')
        parts.append(f'<text x="24" y="{y + 39}" fill="#999" font-family="-apple-system,sans-serif" font-size="12">{strength_label}</text>')
        for theme_index, theme in enumerate(["light", "dark"]):
            base = "#f7f4ec" if theme == "light" else "#17191d"
            ink = "#202124" if theme == "light" else "#f2f3f5"
            swatches = ["#d44a3a", "#4a77d4", "#3b9a61"] if theme == "light" else ["#ff7568", "#78a0ff", "#63ca86"]
            for mode_index, (mode, _) in enumerate(columns):
                row = chosen[(texture, strength)]
                column_index = theme_index * 2 + mode_index
                x = margin + label_w + column_index * (card_w + gap)
                texture_opacity = float(row[f"{mode}_texture"])
                lamp_opacity = float(row[f"{mode}_lamp"])
                parts += [f'<g transform="translate({x} {y})">',
                          f'<rect width="{card_w}" height="{card_h}" rx="10" fill="{base}"/>',
                          f'<text x="16" y="32" fill="{ink}" font-family="Georgia,serif" font-size="18">Readable sample text</text>',
                          f'<text x="16" y="53" fill="{ink}" opacity="0.72" font-family="-apple-system,sans-serif" font-size="11">Texture, tint, and contrast</text>']
                for swatch_index, color in enumerate(swatches):
                    parts.append(f'<rect x="{16 + swatch_index * 48}" y="70" width="38" height="30" rx="5" fill="{color}"/>')
                parts += [f'<rect width="{card_w}" height="{card_h}" rx="10" fill="url(#{texture})" opacity="{texture_opacity:.6f}"/>',
                          f'<rect width="{card_w}" height="{card_h}" rx="10" fill="url(#lamp)" opacity="{lamp_opacity:.6f}"/>',
                          f'<text x="16" y="119" fill="{ink}" font-family="ui-monospace,monospace" font-size="10">T {texture_opacity:.3f} · L {lamp_opacity:.3f}</text>',
                          '</g>']

parts.append('</svg>')
output_path.write_text(''.join(parts), encoding="utf-8")

panel_paths = []
for texture in textures:
    for theme in ["light", "dark"]:
        panel_width = 800
        panel_height = 800
        panel = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{panel_width}" height="{panel_height}" viewBox="0 0 {panel_width} {panel_height}">',
                 '<defs>' + ''.join(defs) + '</defs>',
                 '<rect width="100%" height="100%" fill="#202124"/>',
                 f'<text x="66" y="72" fill="#fff" font-family="-apple-system,sans-serif" font-size="20" font-weight="700">{html.escape(display_names[texture])} · {theme}</text>',
                 '<text x="66" y="96" fill="#b9bdc6" font-family="-apple-system,sans-serif" font-size="13">Late Night / Medium, softness 50%, scale 2</text>']
        for mode_index, (_, mode_title) in enumerate(columns):
            x = 158 + mode_index * (card_w + gap)
            panel.append(f'<text x="{x}" y="118" fill="#ddd" font-family="-apple-system,sans-serif" font-size="12">{mode_title}</text>')
        base = "#f7f4ec" if theme == "light" else "#17191d"
        ink = "#202124" if theme == "light" else "#f2f3f5"
        swatches = ["#d44a3a", "#4a77d4", "#3b9a61"] if theme == "light" else ["#ff7568", "#78a0ff", "#63ca86"]
        for strength_index, (strength_label, strength) in enumerate(strengths):
            y = 126 + strength_index * (card_h + gap)
            panel.append(f'<text x="66" y="{y + 25}" fill="#ddd" font-family="-apple-system,sans-serif" font-size="13">{strength_label}</text>')
            for mode_index, (mode, _) in enumerate(columns):
                row = chosen[(texture, strength)]
                x = 158 + mode_index * (card_w + gap)
                texture_opacity = float(row[f"{mode}_texture"])
                lamp_opacity = float(row[f"{mode}_lamp"])
                panel += [f'<g transform="translate({x} {y})">',
                          f'<rect width="{card_w}" height="{card_h}" rx="10" fill="{base}"/>',
                          f'<text x="16" y="32" fill="{ink}" font-family="Georgia,serif" font-size="18">Readable sample text</text>',
                          f'<text x="16" y="53" fill="{ink}" opacity="0.72" font-family="-apple-system,sans-serif" font-size="11">Texture, tint, and contrast</text>']
                for swatch_index, color in enumerate(swatches):
                    panel.append(f'<rect x="{16 + swatch_index * 48}" y="70" width="38" height="30" rx="5" fill="{color}"/>')
                panel += [f'<rect width="{card_w}" height="{card_h}" rx="10" fill="url(#{texture})" opacity="{texture_opacity:.6f}"/>',
                          f'<rect width="{card_w}" height="{card_h}" rx="10" fill="url(#lamp)" opacity="{lamp_opacity:.6f}"/>',
                          f'<text x="16" y="119" fill="{ink}" font-family="ui-monospace,monospace" font-size="10">T {texture_opacity:.3f} · L {lamp_opacity:.3f}</text>',
                          '</g>']
        panel.append('</svg>')
        panel_path = output_path.with_name(f"contact-{display_names[texture].lower().replace(' ', '-')}-{theme}.svg")
        panel_path.write_text(''.join(panel), encoding="utf-8")
        panel_paths.append(panel_path)

print(output_path)
for panel_path in panel_paths:
    print(panel_path)
