#!/bin/bash
set -e

# Generate BetterPasting app icon
# Creates a modern icon with the clipboard concept similar to the menu bar icon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICONSET_DIR="$SCRIPT_DIR/BetterPasting/Resources/AppIcon.iconset"
ICNS_FILE="$SCRIPT_DIR/BetterPasting/Resources/AppIcon.icns"

echo "=== Generating BetterPasting App Icon ==="

# Create iconset directory
mkdir -p "$ICONSET_DIR"

# Icon sizes required for macOS .icns
SIZES=(16 32 128 256 512)

# Generate icons at each size
for size in "${SIZES[@]}"; do
    echo "Generating ${size}x${size}..."

    # Regular size
    cat > /tmp/icon_svg_${size}.svg << EOF
<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bgGradient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#667EEA"/>
      <stop offset="100%" style="stop-color:#764BA2"/>
    </linearGradient>
    <linearGradient id="clipboardGradient" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#FFFFFF"/>
      <stop offset="100%" style="stop-color:#E8E8E8"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="2" stdDeviation="3" flood-opacity="0.3"/>
    </filter>
  </defs>

  <!-- Background with rounded corners -->
  <rect x="0" y="0" width="${size}" height="${size}" rx="$(echo "$size * 0.22" | bc)" ry="$(echo "$size * 0.22" | bc)" fill="url(#bgGradient)"/>

  <!-- Clipboard body -->
  <g transform="translate($(echo "$size * 0.22" | bc), $(echo "$size * 0.18" | bc))">
    <!-- Main clipboard rectangle -->
    <rect x="0" y="$(echo "$size * 0.08" | bc)"
          width="$(echo "$size * 0.56" | bc)"
          height="$(echo "$size * 0.62" | bc)"
          rx="$(echo "$size * 0.04" | bc)"
          fill="url(#clipboardGradient)"
          filter="url(#shadow)"/>

    <!-- Clipboard clip at top -->
    <rect x="$(echo "$size * 0.14" | bc)" y="0"
          width="$(echo "$size * 0.28" | bc)"
          height="$(echo "$size * 0.14" | bc)"
          rx="$(echo "$size * 0.03" | bc)"
          fill="#A0AEC0"/>

    <!-- Inner clip detail -->
    <rect x="$(echo "$size * 0.18" | bc)" y="$(echo "$size * 0.03" | bc)"
          width="$(echo "$size * 0.20" | bc)"
          height="$(echo "$size * 0.06" | bc)"
          rx="$(echo "$size * 0.02" | bc)"
          fill="#718096"/>

    <!-- Text lines on clipboard -->
    <rect x="$(echo "$size * 0.08" | bc)" y="$(echo "$size * 0.22" | bc)"
          width="$(echo "$size * 0.40" | bc)" height="$(echo "$size * 0.04" | bc)"
          rx="$(echo "$size * 0.02" | bc)" fill="#667EEA" opacity="0.8"/>
    <rect x="$(echo "$size * 0.08" | bc)" y="$(echo "$size * 0.30" | bc)"
          width="$(echo "$size * 0.32" | bc)" height="$(echo "$size * 0.04" | bc)"
          rx="$(echo "$size * 0.02" | bc)" fill="#667EEA" opacity="0.6"/>
    <rect x="$(echo "$size * 0.08" | bc)" y="$(echo "$size * 0.38" | bc)"
          width="$(echo "$size * 0.36" | bc)" height="$(echo "$size * 0.04" | bc)"
          rx="$(echo "$size * 0.02" | bc)" fill="#667EEA" opacity="0.4"/>
  </g>
</svg>
EOF

    # Convert SVG to PNG using qlmanage (built into macOS)
    # Alternative: use sips if available
    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert -w "$size" -h "$size" "/tmp/icon_svg_${size}.svg" -o "$ICONSET_DIR/icon_${size}x${size}.png"
    elif command -v convert &> /dev/null; then
        convert -background none -resize "${size}x${size}" "/tmp/icon_svg_${size}.svg" "$ICONSET_DIR/icon_${size}x${size}.png"
    else
        # Fallback: create a simple colored icon using sips
        echo "Note: Install librsvg (brew install librsvg) for SVG support. Using fallback method."

        # Create a simple gradient-like icon using Python
        python3 << PYTHON_EOF
import struct
import zlib

def create_png(filename, size):
    # Create a simple purple gradient icon with clipboard-like shape

    def rgba_to_bytes(r, g, b, a=255):
        return bytes([r, g, b, a])

    # Create image data
    raw_data = []
    center = size // 2
    corner_radius = int(size * 0.22)

    for y in range(size):
        row = [0]  # Filter byte
        for x in range(size):
            # Calculate gradient color (purple gradient)
            t = (x + y) / (2 * size)
            r = int(102 + (118 - 102) * t)
            g = int(126 + (75 - 126) * t)
            b = int(234 + (162 - 234) * t)

            # Check if we're in the rounded rectangle
            in_rect = True

            # Check corners
            corners = [
                (corner_radius, corner_radius),
                (size - corner_radius - 1, corner_radius),
                (corner_radius, size - corner_radius - 1),
                (size - corner_radius - 1, size - corner_radius - 1)
            ]

            if x < corner_radius and y < corner_radius:
                dist = ((x - corner_radius) ** 2 + (y - corner_radius) ** 2) ** 0.5
                in_rect = dist <= corner_radius
            elif x >= size - corner_radius and y < corner_radius:
                dist = ((x - (size - corner_radius - 1)) ** 2 + (y - corner_radius) ** 2) ** 0.5
                in_rect = dist <= corner_radius
            elif x < corner_radius and y >= size - corner_radius:
                dist = ((x - corner_radius) ** 2 + (y - (size - corner_radius - 1)) ** 2) ** 0.5
                in_rect = dist <= corner_radius
            elif x >= size - corner_radius and y >= size - corner_radius:
                dist = ((x - (size - corner_radius - 1)) ** 2 + (y - (size - corner_radius - 1)) ** 2) ** 0.5
                in_rect = dist <= corner_radius

            if in_rect:
                # Check if we're in the clipboard area (white)
                clip_x = int(size * 0.22)
                clip_y = int(size * 0.26)
                clip_w = int(size * 0.56)
                clip_h = int(size * 0.62)
                clip_radius = int(size * 0.04)

                in_clipboard = (clip_x <= x < clip_x + clip_w and
                               clip_y <= y < clip_y + clip_h)

                # Clipboard clip at top
                clip_top_x = int(size * 0.36)
                clip_top_y = int(size * 0.18)
                clip_top_w = int(size * 0.28)
                clip_top_h = int(size * 0.14)
                in_clip_top = (clip_top_x <= x < clip_top_x + clip_top_w and
                              clip_top_y <= y < clip_top_y + clip_top_h)

                if in_clipboard:
                    # White clipboard
                    r, g, b = 255, 255, 255

                    # Draw text lines
                    line_x = int(size * 0.30)
                    line_h = int(size * 0.04)
                    lines = [
                        (int(size * 0.40), int(size * 0.40)),  # y, width
                        (int(size * 0.48), int(size * 0.32)),
                        (int(size * 0.56), int(size * 0.36)),
                    ]
                    for line_y, line_w in lines:
                        if (line_x <= x < line_x + line_w and
                            line_y <= y < line_y + line_h):
                            r, g, b = 102, 126, 234  # Purple line
                elif in_clip_top:
                    r, g, b = 160, 174, 192  # Gray clip

                row.extend([r, g, b, 255])
            else:
                row.extend([0, 0, 0, 0])

        raw_data.append(bytes(row))

    raw_data = b''.join(raw_data)

    def png_chunk(chunk_type, data):
        chunk_len = struct.pack('>I', len(data))
        chunk_crc = struct.pack('>I', zlib.crc32(chunk_type + data) & 0xffffffff)
        return chunk_len + chunk_type + data + chunk_crc

    # PNG signature
    signature = b'\x89PNG\r\n\x1a\n'

    # IHDR chunk
    ihdr_data = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    ihdr = png_chunk(b'IHDR', ihdr_data)

    # IDAT chunk
    compressed = zlib.compress(raw_data, 9)
    idat = png_chunk(b'IDAT', compressed)

    # IEND chunk
    iend = png_chunk(b'IEND', b'')

    with open(filename, 'wb') as f:
        f.write(signature + ihdr + idat + iend)

create_png('$ICONSET_DIR/icon_${size}x${size}.png', $size)
PYTHON_EOF
    fi

    # Create @2x version
    size2x=$((size * 2))
    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert -w "$size2x" -h "$size2x" "/tmp/icon_svg_${size}.svg" -o "$ICONSET_DIR/icon_${size}x${size}@2x.png"
    elif command -v convert &> /dev/null; then
        convert -background none -resize "${size2x}x${size2x}" "/tmp/icon_svg_${size}.svg" "$ICONSET_DIR/icon_${size}x${size}@2x.png"
    else
        python3 << PYTHON_EOF
import struct
import zlib

def create_png(filename, size):
    # Create a simple purple gradient icon with clipboard-like shape

    raw_data = []
    center = size // 2
    corner_radius = int(size * 0.22)

    for y in range(size):
        row = [0]  # Filter byte
        for x in range(size):
            # Calculate gradient color (purple gradient)
            t = (x + y) / (2 * size)
            r = int(102 + (118 - 102) * t)
            g = int(126 + (75 - 126) * t)
            b = int(234 + (162 - 234) * t)

            # Check if we're in the rounded rectangle
            in_rect = True

            if x < corner_radius and y < corner_radius:
                dist = ((x - corner_radius) ** 2 + (y - corner_radius) ** 2) ** 0.5
                in_rect = dist <= corner_radius
            elif x >= size - corner_radius and y < corner_radius:
                dist = ((x - (size - corner_radius - 1)) ** 2 + (y - corner_radius) ** 2) ** 0.5
                in_rect = dist <= corner_radius
            elif x < corner_radius and y >= size - corner_radius:
                dist = ((x - corner_radius) ** 2 + (y - (size - corner_radius - 1)) ** 2) ** 0.5
                in_rect = dist <= corner_radius
            elif x >= size - corner_radius and y >= size - corner_radius:
                dist = ((x - (size - corner_radius - 1)) ** 2 + (y - (size - corner_radius - 1)) ** 2) ** 0.5
                in_rect = dist <= corner_radius

            if in_rect:
                clip_x = int(size * 0.22)
                clip_y = int(size * 0.26)
                clip_w = int(size * 0.56)
                clip_h = int(size * 0.62)

                in_clipboard = (clip_x <= x < clip_x + clip_w and
                               clip_y <= y < clip_y + clip_h)

                clip_top_x = int(size * 0.36)
                clip_top_y = int(size * 0.18)
                clip_top_w = int(size * 0.28)
                clip_top_h = int(size * 0.14)
                in_clip_top = (clip_top_x <= x < clip_top_x + clip_top_w and
                              clip_top_y <= y < clip_top_y + clip_top_h)

                if in_clipboard:
                    r, g, b = 255, 255, 255

                    line_x = int(size * 0.30)
                    line_h = int(size * 0.04)
                    lines = [
                        (int(size * 0.40), int(size * 0.40)),
                        (int(size * 0.48), int(size * 0.32)),
                        (int(size * 0.56), int(size * 0.36)),
                    ]
                    for line_y, line_w in lines:
                        if (line_x <= x < line_x + line_w and
                            line_y <= y < line_y + line_h):
                            r, g, b = 102, 126, 234
                elif in_clip_top:
                    r, g, b = 160, 174, 192

                row.extend([r, g, b, 255])
            else:
                row.extend([0, 0, 0, 0])

        raw_data.append(bytes(row))

    raw_data = b''.join(raw_data)

    def png_chunk(chunk_type, data):
        chunk_len = struct.pack('>I', len(data))
        chunk_crc = struct.pack('>I', zlib.crc32(chunk_type + data) & 0xffffffff)
        return chunk_len + chunk_type + data + chunk_crc

    signature = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    ihdr = png_chunk(b'IHDR', ihdr_data)
    compressed = zlib.compress(raw_data, 9)
    idat = png_chunk(b'IDAT', compressed)
    iend = png_chunk(b'IEND', b'')

    with open(filename, 'wb') as f:
        f.write(signature + ihdr + idat + iend)

create_png('$ICONSET_DIR/icon_${size}x${size}@2x.png', $size2x)
PYTHON_EOF
    fi

    rm -f "/tmp/icon_svg_${size}.svg"
done

# Convert iconset to icns
echo "Creating .icns file..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"

# Clean up iconset
rm -rf "$ICONSET_DIR"

echo "=== Icon Generation Complete ==="
echo "Icon file: $ICNS_FILE"
