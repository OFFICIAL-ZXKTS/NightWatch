import os
import re

def parse_flf(flf_path):
    with open(flf_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    header = lines[0].split()
    hardblank = header[0][-1]
    height = int(header[1])
    comment_lines = int(header[5])
    char_lines = lines[1 + comment_lines:]
    chars = {}
    idx = 0
    for code in range(32, 127):
        char_glyph = []
        for h in range(height):
            if idx >= len(char_lines):
                break
            raw_line = char_lines[idx].rstrip('\r\n')
            while raw_line.endswith('@'):
                raw_line = raw_line[:-1]
            raw_line = raw_line.replace(hardblank, ' ')
            char_glyph.append(raw_line)
            idx += 1
        chars[chr(code)] = char_glyph
    return chars, height

def render_ascii_lines(text, chars, height):
    lines = ['' for _ in range(height)]
    for ch in text:
        glyph = chars.get(ch, [' ' * 4 for _ in range(height)])
        for h in range(height):
            lines[h] += glyph[h]
    return lines

def generate_svg(text_lines, title, theme="dark", total_width=760, total_height=88):
    # Palette matching MiniMax Code wordmarks exactly
    if theme == "dark":
        y_colors = {
            0: "#93D2FF",
            1: "#93D2FF",
            2: "#68C0FF",
            3: "#68C0FF",
            4: "#3DAEFF",
            5: "#3DAEFF",
        }
    else:
        y_colors = {
            0: "#3DAEFF",
            1: "#3DAEFF",
            2: "#0094FC",
            3: "#0094FC",
            4: "#0077D9",
            5: "#0077D9",
        }
    
    y_positions = [17, 29, 41, 53, 65, 77]
    char_width = 7.8
    
    # Calculate centering
    max_cols = max(len(line) for line in text_lines[:6])
    rendered_width = max_cols * char_width
    start_x = round((total_width - rendered_width) / 2.0, 1)
    if start_x < 10.0:
        total_width = int(rendered_width + 48)
        start_x = round((total_width - rendered_width) / 2.0, 1)

    svg_parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_width}" height="{total_height}" viewBox="0 0 {total_width} {total_height}" role="img" aria-label="{title}">',
        f'<title>{title}</title>',
        '<g font-family="Menlo,Consolas,monospace" font-size="13">'
    ]

    for row_idx, line in enumerate(text_lines[:6]):
        y = y_positions[row_idx]
        fill = y_colors[row_idx]
        for col_idx, ch in enumerate(line):
            if ch != ' ':
                x = round(start_x + col_idx * char_width, 1)
                escaped_ch = ch
                if ch == '&': escaped_ch = '&amp;'
                elif ch == '<': escaped_ch = '&lt;'
                elif ch == '>': escaped_ch = '&gt;'
                elif ch == '"': escaped_ch = '&quot;'
                svg_parts.append(
                    f'<text x="{x}" y="{y}" fill="{fill}" textLength="{char_width}" lengthAdjust="spacingAndGlyphs">{escaped_ch}</text>'
                )

    svg_parts.append('</g>')
    svg_parts.append('</svg>')
    svg_parts.append('')
    return '\n'.join(svg_parts)

if __name__ == '__main__':
    base_dir = r'c:\Users\diyaj\Downloads\Shutdown'
    flf_path = os.path.join(base_dir, 'ansi_shadow.flf')
    chars, height = parse_flf(flf_path)
    
    # Render "NIGHT WATCH" with clean spacing
    lines = render_ascii_lines("NIGHT WATCH", chars, height)
    
    dark_svg = generate_svg(lines, "NightWatch", theme="dark", total_width=760, total_height=88)
    with open(os.path.join(base_dir, 'assets', 'wordmark-dark.svg'), 'w', encoding='utf-8') as f:
        f.write(dark_svg)
        
    light_svg = generate_svg(lines, "NightWatch", theme="light", total_width=760, total_height=88)
    with open(os.path.join(base_dir, 'assets', 'wordmark-light.svg'), 'w', encoding='utf-8') as f:
        f.write(light_svg)
        
    # Also update banner.svg to point to dark wordmark as compatibility fallback
    with open(os.path.join(base_dir, 'assets', 'banner.svg'), 'w', encoding='utf-8') as f:
        f.write(dark_svg)
        
    print("Successfully built assets/wordmark-dark.svg, assets/wordmark-light.svg, and assets/banner.svg!")
