// Generates the game's PNG assets with zero dependencies.
// The image is rendered by sampling analytic shapes per pixel, then encoded as
// a real PNG (IHDR + IDAT with zlib deflate + IEND) so Godot imports them
// exactly like any hand-drawn art.
import { deflateSync } from 'node:zlib'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

// ---------------------------------------------------------------- PNG encoder

const CRC_TABLE = (() => {
  const table = new Int32Array(256)
  for (let n = 0; n < 256; n += 1) {
    let c = n
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    table[n] = c
  }
  return table
})()

function crc32(buf) {
  let c = -1
  for (let i = 0; i < buf.length; i += 1) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8)
  return (c ^ -1) >>> 0
}

function chunk(type, data) {
  const length = Buffer.alloc(4)
  length.writeUInt32BE(data.length, 0)
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(body), 0)
  return Buffer.concat([length, body, crc])
}

function encodePNG(width, height, rgba) {
  const stride = width * 4
  const raw = Buffer.alloc((stride + 1) * height)
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0 // filter: none
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride)
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = 6 // colour type: RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

// ------------------------------------------------------------- 2D canvas

class Canvas {
  constructor(width, height) {
    this.width = width
    this.height = height
    this.px = Buffer.alloc(width * height * 4)
  }

  // Source-over compositing of one RGBA sample.
  blend(x, y, [r, g, b, a]) {
    if (a <= 0) return
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return
    const i = (y * this.width + x) * 4
    const src = a / 255
    const dstA = this.px[i + 3] / 255
    const outA = src + dstA * (1 - src)
    if (outA <= 0) return
    for (let c = 0; c < 3; c += 1) {
      const dst = this.px[i + c]
      const value = ([r, g, b][c] * src + dst * dstA * (1 - src)) / outA
      this.px[i + c] = Math.max(0, Math.min(255, Math.round(value)))
    }
    this.px[i + 3] = Math.round(outA * 255)
  }

  // Anti-aliased fill of an implicit shape: `fn(x, y)` returns signed coverage
  // in 0..1 (1 = fully inside).
  fill(fn, color) {
    for (let y = 0; y < this.height; y += 1) {
      for (let x = 0; x < this.width; x += 1) {
        const coverage = fn(x + 0.5, y + 0.5)
        if (coverage <= 0) continue
        this.blend(x, y, [color[0], color[1], color[2], (color[3] ?? 255) * coverage])
      }
    }
  }

  toPNG() {
    return encodePNG(this.width, this.height, this.px)
  }
}

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v)
// Coverage from a signed distance: 1 inside, fading over one pixel at the edge.
const cover = (distance) => clamp01(0.5 - distance)

const disc = (cx, cy, r) => (x, y) => cover(Math.hypot(x - cx, y - cy) - r)
const ellipse = (cx, cy, rx, ry, angle = 0) => (x, y) => {
  const dx = x - cx
  const dy = y - cy
  const c = Math.cos(-angle)
  const s = Math.sin(-angle)
  const ux = dx * c - dy * s
  const uy = dx * s + dy * c
  return cover(Math.hypot(ux / rx, uy / ry) * Math.min(rx, ry) - Math.min(rx, ry))
}

function rect(x0, y0, x1, y1) {
  return (x, y) => cover(Math.max(x0 - x, x - x1, y0 - y, y - y1))
}

function roundRect(x0, y0, x1, y1, r) {
  return (x, y) => {
    const cx = Math.max(x0 + r, Math.min(x, x1 - r))
    const cy = Math.max(y0 + r, Math.min(y, y1 - r))
    return cover(Math.hypot(x - cx, y - cy) - r + (x >= x0 && x <= x1 && y >= y0 && y <= y1 ? 1 : 0))
  }
}

// Union of shapes: keep the strongest coverage.
const union = (...shapes) => (x, y) => shapes.reduce((m, s) => Math.max(m, s(x, y)), 0)
// Intersection: keep the weakest coverage.
const intersect = (...shapes) => (x, y) => shapes.reduce((m, s) => Math.min(m, s(x, y)), 1)
// Difference: base minus cutters.
const cut = (base, ...cutters) => (x, y) =>
  cutters.reduce((m, c) => Math.min(m, 1 - c(x, y)), base(x, y))

const lerp = (a, b, t) => a + (b - a) * t

// ------------------------------------------------------------------ sprites

// A mosquito seen from above: slim striped abdomen, rounded thorax, a pair of
// swept translucent wings, six thin legs and a needle proboscis. `wing` shifts
// the wing sweep between flap frames.
//
// Style rules that keep it readable at 2x zoom on a bright window:
//   - one dark silhouette colour for every appendage, so the shape reads first
//   - wings translucent and outlined, never solid
//   - a soft shadow under the body to lift it off the glass
function drawMosquito(canvas, wing, squash = 1) {
  const cx = canvas.width / 2
  const cy = canvas.height / 2
  const dark = [42, 33, 28, 255]
  const shell = [58, 44, 36, 255]
  const stripe = [24, 18, 15, 255]
  const wingFill = [244, 250, 255, 138]
  const wingEdge = [150, 176, 198, 170]
  const shadow = [0, 0, 0, 26]

  const squashX = 1 / Math.max(0.4, squash)
  const squashY = squash
  const shaped = (shape) => (x, y) => shape(cx + (x - cx) * squashX, cy + (y - cy) * squashY)

  // Soft contact shadow, drawn first so everything sits on top of it.
  canvas.fill(shaped(ellipse(cx, cy + 3, 13, 17)), shadow)

  // Wings: outline pass first, then the translucent membrane. They stay long
  // (a mosquito's wings overhang the abdomen) but read as wings, not blades.
  const wingPaths = [-1, 1].map((side) => {
    const rootX = cx + side * 2.5
    const rootY = cy - 5
    const reach = 24
    const angle = side * (1.02 + wing) - Math.PI / 2
    // Tip swings a little further than the sweep so flapping looks elastic.
    return { rootX, rootY, reach, angle, tipAngle: angle + side * 0.18 }
  })

  for (const path of wingPaths) {
    for (let t = 0; t <= 1; t += 0.008) {
      const angle = lerp(path.angle, path.tipAngle, t)
      const x = path.rootX + Math.cos(angle) * path.reach * t
      const y = path.rootY + Math.sin(angle) * path.reach * t
      // Narrow at the root, widest past the middle, rounded tip.
      const halfWidth = 8.4 * Math.sin(Math.PI * (0.08 + 0.92 * t)) ** 0.75
      canvas.fill(union(disc(x, y + halfWidth, 1.5), disc(x, y - halfWidth, 1.5)), wingEdge)
    }
    for (let t = 0; t <= 1; t += 0.008) {
      const angle = lerp(path.angle, path.tipAngle, t)
      const x = path.rootX + Math.cos(angle) * path.reach * t
      const y = path.rootY + Math.sin(angle) * path.reach * t
      const halfWidth = 8.4 * Math.sin(Math.PI * (0.08 + 0.92 * t)) ** 0.75
      canvas.fill(union(disc(x, y + halfWidth * 0.88, 1.2), disc(x, y - halfWidth * 0.88, 1.2)), wingFill)
    }
  }

  // Legs: short, thin, and all swept backwards so the body stays the subject.
  // Each pair hinges at the thorax, bends at a knee, and trails past the body.
  const legPairs = [
    { base: -5.0, spread: 0.62, knee: 10, tip: 19 },
    { base: -2.0, spread: 0.5, knee: 11, tip: 21 },
    { base: 3.0, spread: 0.42, knee: 11, tip: 20 },
  ]
  legPairs.forEach((pair, index) => {
    const rootY = cy + pair.base
    for (const side of [-1, 1]) {
      // Forward, mostly-sideways, then hooked backwards at the knee.
      const midAngle = side > 0 ? 0.5 - index * 0.25 : Math.PI - (0.5 - index * 0.25)
      const tipAngle = side > 0 ? 1.35 : Math.PI - 1.35
      const rootX = cx + side * 2
      const kneeX = rootX + Math.cos(midAngle) * pair.knee
      const kneeY = rootY + Math.sin(midAngle) * pair.knee * pair.spread + pair.knee * 0.35
      const tipX = kneeX + Math.cos(tipAngle) * (pair.tip - pair.knee)
      const tipY = kneeY + Math.sin(tipAngle) * (pair.tip - pair.knee) * 0.5 + 4
      for (let t = 0; t <= 1; t += 0.025) {
        const x = lerp(lerp(rootX, kneeX, t), lerp(kneeX, tipX, t), t)
        const y = lerp(lerp(rootY, kneeY, t), lerp(kneeY, tipY, t), t)
        canvas.fill(shaped(disc(x, y, 1.35 - t * 0.6)), dark)
      }
    }
  })

  // Abdomen: tapered and striped, pointing away from the head.
  for (let t = 0; t <= 1; t += 0.008) {
    const y = cy + 1 + t * 16
    const radius = 5.6 * (1 - t * 0.66)
    canvas.fill(shaped(disc(cx, y, radius)), t > 0.7 ? shell : dark)
  }
  for (const t of [0.26, 0.54, 0.82]) {
    const y = cy + 1 + t * 16
    const radius = 5.6 * (1 - t * 0.66)
    canvas.fill(shaped(disc(cx, y, radius * 0.97)), stripe)
  }

  // Thorax: rounded shell plate with a lighter highlight.
  canvas.fill(shaped(ellipse(cx, cy - 3, 6.4, 7.6)), dark)
  canvas.fill(shaped(ellipse(cx - 1.4, cy - 4.8, 3.2, 3.6)), [104, 84, 68, 190])

  // Head, eyes and proboscis.
  canvas.fill(shaped(disc(cx, cy - 12, 4.0)), dark)
  canvas.fill(shaped(disc(cx - 2.0, cy - 13, 1.4)), [18, 13, 11, 255])
  canvas.fill(shaped(disc(cx + 2.0, cy - 13, 1.4)), [18, 13, 11, 255])
  canvas.fill(shaped(rect(cx - 0.7, cy - 26, cx + 0.7, cy - 13)), stripe)
}

function mosquitoFrame(wing, squash = 1) {
  const canvas = new Canvas(80, 80)
  drawMosquito(canvas, wing, squash)
  return canvas.toPNG()
}

// A blood splat used as the "hit" mark: irregular blob plus droplets.
function splat() {
  const canvas = new Canvas(96, 96)
  const red = [150, 24, 30, 255]
  const dark = [104, 14, 20, 255]
  const lobes = [
    [48, 48, 22],
    [31, 39, 13],
    [63, 34, 11],
    [36, 63, 12],
    [62, 60, 10],
  ]
  for (const [cx, cy, r] of lobes) canvas.fill(disc(cx, cy, r), red)
  canvas.fill(union(disc(48, 48, 12), disc(43, 45, 8)), dark)
  const drops = [
    [16, 22, 4],
    [80, 26, 5],
    [22, 74, 3.5],
    [76, 72, 4.5],
    [48, 12, 3],
    [50, 86, 3.5],
    [8, 50, 3],
    [88, 52, 3],
  ]
  for (const [cx, cy, r] of drops) canvas.fill(disc(cx, cy, r), red)
  return canvas.toPNG()
}

// The window the mosquitoes land on: sky, glass with a highlight streak,
// muntin bars, and a frame with corner screws.
function windowBackground(width, height) {
  const canvas = new Canvas(width, height)
  const frame = 34
  const glassTop = frame
  const glassBottom = height - frame

  // Sky gradient behind the glass.
  for (let y = 0; y < height; y += 1) {
    const t = y / height
    const color = [
      Math.round(lerp(150, 196, t)),
      Math.round(lerp(196, 226, t)),
      Math.round(lerp(232, 244, t)),
      255,
    ]
    canvas.fill(rect(0, y, width, y + 1), color)
  }
  // A hint of clouds / city silhouette so the glass reads as a window.
  for (const [cx, cy, rx, ry] of [[180, 120, 90, 34], [300, 96, 70, 26], [520, 150, 110, 30]]) {
    canvas.fill(ellipse(cx, cy, rx, ry), [255, 255, 255, 120])
  }
  for (const [x0, x1, top] of [[70, 130, 300], [140, 210, 268], [230, 300, 292], [330, 380, 262], [470, 540, 286]]) {
    canvas.fill(rect(x0, top, x1, glassBottom), [126, 148, 166, 90])
  }

  // Glass tint + diagonal highlight.
  canvas.fill(rect(frame, glassTop, width - frame, glassBottom), [210, 232, 244, 46])
  for (let i = 0; i < 90; i += 1) {
    const x = 60 + i * 7
    canvas.fill(
      intersect(rect(0, glassTop, width, glassBottom), (px, py) => cover(Math.abs(px - x - py * 0.55) - 12)),
      [255, 255, 255, 16],
    )
  }

  // Aluminium frame.
  const frameColor = [222, 226, 230, 255]
  const frameDark = [176, 182, 188, 255]
  canvas.fill(rect(0, 0, width, height), frameColor)
  canvas.fill(rect(frame, glassTop, width - frame, glassBottom), [200, 220, 232, 255])
  canvas.fill(rect(0, 0, width, 4), [246, 248, 250, 255])
  canvas.fill(rect(0, height - 4, width, height), frameDark)
  canvas.fill(rect(0, 0, 4, height), [246, 248, 250, 255])
  canvas.fill(rect(width - 4, 0, width, height), frameDark)

  // Muntin bars dividing the glass into four panes.
  const midX = Math.round(width / 2)
  const midY = Math.round((glassTop + glassBottom) / 2)
  for (const [x0, y0, x1, y1] of [
    [midX - 5, glassTop, midX + 5, glassBottom],
    [frame, midY - 5, width - frame, midY + 5],
  ]) {
    canvas.fill(rect(x0, y0, x1, y1), frameColor)
    canvas.fill(rect(x0, y1 - 3, x1, y1), frameDark)
  }

  // Screws at the four corners.
  for (const [cx, cy] of [[17, 17], [width - 17, 17], [17, height - 17], [width - 17, height - 17]]) {
    canvas.fill(disc(cx, cy, 6), frameDark)
    canvas.fill(disc(cx, cy, 4), [232, 236, 240, 255])
    canvas.fill(rect(cx - 3.5, cy - 0.8, cx + 3.5, cy + 0.8), [150, 156, 162, 255])
  }

  return canvas.toPNG()
}

// ------------------------------------------------------------------ emit

const outDir = join(process.cwd(), 'assets', 'sprites')
mkdirSync(outDir, { recursive: true })

const written = []
function write(name, buffer) {
  const path = join(outDir, name)
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, buffer)
  written.push(name)
}

// Four flap frames sweeping the wings forward and back.
const wingSweep = [0.0, 0.42, 0.0, -0.42]
wingSweep.forEach((wing, index) => write(`mosquito_${index}.png`, mosquitoFrame(wing)))
write('splat.png', splat())
write('background.png', windowBackground(1280, 720))

process.stdout.write(`generated ${written.length} PNGs in ${outDir}\n${written.join('\n')}\n`)
