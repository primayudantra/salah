#!/usr/bin/env bash
# Regenerates the bundled chime and app icon. Both are original, generated here, so no third-party licenses apply.
set -euo pipefail
cd "$(dirname "$0")/.."
RES=App/SalahMac/Resources
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Soft two-note chime (sine partials with exponential decay).
python3 - "$TMP/chime.wav" <<'PY'
import math, struct, sys, wave
rate, dur = 44100, 1.6
notes = [(880.0, 0.0), (1318.5, 0.18)]
frames = []
for i in range(int(rate * dur)):
    t = i / rate
    v = 0.0
    for f, start in notes:
        if t >= start:
            u = t - start
            env = math.exp(-u * 3.2) * min(1.0, u / 0.01)
            v += env * (math.sin(2 * math.pi * f * u) + 0.25 * math.sin(4 * math.pi * f * u))
    frames.append(struct.pack('<h', int(max(-1, min(1, v * 0.28)) * 32767)))
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(b''.join(frames))
PY
afconvert -f caff -d LEI16 "$TMP/chime.wav" "$RES/Sounds/salah-chime.caf"

# App icon: crimson rounded square with a crescent and a small timeline.
cat > "$TMP/icon.swift" <<'SWIFT'
import AppKit
let out = CommandLine.arguments[1]
for (size, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSColor(srgbRed: 0.631, green: 0.059, blue: 0.141, alpha: 1).setFill(); bg.fill()
    let fg = NSColor(srgbRed: 0.984, green: 0.933, blue: 0.941, alpha: 1)
    // crescent
    let c = NSPoint(x: rect.midX + rect.width * 0.08, y: rect.midY + rect.height * 0.08), r = rect.width * 0.26
    let moon = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    let cut = NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.55, y: c.y - r * 0.8, width: 2 * r, height: 2 * r))
    NSGraphicsContext.current!.saveGraphicsState()
    moon.addClip()
    fg.setFill(); moon.fill()
    NSColor(srgbRed: 0.631, green: 0.059, blue: 0.141, alpha: 1).setFill(); cut.fill()
    NSGraphicsContext.current!.restoreGraphicsState()
    // timeline dots
    let x = rect.minX + rect.width * 0.22
    let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: rect.minY + rect.height * 0.18)); line.line(to: NSPoint(x: x, y: rect.maxY - rect.height * 0.18))
    line.lineWidth = max(1, s * 0.012); fg.withAlphaComponent(0.6).setStroke(); line.stroke()
    for i in 0..<5 {
        let y = rect.minY + rect.height * (0.18 + 0.16 * CGFloat(i)), d = rect.width * 0.06
        fg.setFill(); NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
SWIFT
mkdir -p "$TMP/AppIcon.iconset"
swift "$TMP/icon.swift" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$RES/AppIcon.icns"
echo "Assets written to $RES"
