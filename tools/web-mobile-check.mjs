// Throwaway mobile check: serves the web build and loads it with Chrome's device
// emulation on, the same way DevTools' device toolbar does. Reports the CSS
// viewport, the canvas element size and the drawing buffer size, then saves a
// screenshot so the mobile layout can be compared with a real phone.
//
//   node tools/web-mobile-check.mjs <width> <height> <port> <shot.png>
import { createServer } from 'node:http'
import { writeFile } from 'node:fs/promises'
import { join, extname } from 'node:path'
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
import * as fsCallback from 'node:fs'
import { promisify } from 'node:util'

const WIDTH = Number(process.argv[2] ?? 390)
const HEIGHT = Number(process.argv[3] ?? 844)
const PORT = Number(process.argv[4] ?? 8140)
const SHOT = process.argv[5] ?? 'E:\\software\\juegos\\mataCudos\\build\\mobile-shot.png'
const ROOT = process.env.WEB_ROOT ?? 'E:\\software\\juegos\\mataCudos\\build\\web'
const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
const PROFILE = `${process.env.TEMP}\\dsh-chrome-mobile`
// `--no-touch` runs the check as a desktop: no device metrics override and no
// touch emulation, so the hint must stay hidden.
const AS_DESKTOP = process.argv.includes('--no-touch')

const require = createRequire('E:\\game dev\\godot-mcp\\server\\package.json')
const WebSocket = require('ws')
const stat = promisify(fsCallback.stat)
const readFile = promisify(fsCallback.readFile)

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
}

const server = createServer(async (request, response) => {
  const relative = decodeURIComponent(new URL(request.url, 'http://x').pathname).replace(/^\/+/, '') || 'index.html'
  try {
    const path = join(ROOT, relative)
    await stat(path)
    const body = await readFile(path)
    response.writeHead(200, {
      'Content-Type': TYPES[extname(path).toLowerCase()] ?? 'application/octet-stream',
      'Content-Length': body.length,
    })
    response.end(body)
  } catch (error) {
    response.writeHead(404).end('not found')
    console.log(`404 ${relative} (${error.code ?? error.message})`)
  }
})
await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve))
console.log(`serving on http://127.0.0.1:${PORT}/ emulando ${WIDTH}x${HEIGHT}`)

const chrome = spawn(CHROME, [
  '--headless=new',
  '--disable-gpu',
  '--enable-unsafe-swiftshader',
  '--use-gl=angle',
  '--use-angle=swiftshader',
  `--window-size=${WIDTH},${HEIGHT}`,
  `--user-data-dir=${PROFILE}`,
  '--no-first-run',
  '--disable-extensions',
  '--disable-background-timer-throttling',
  '--disable-renderer-backgrounding',
  // A mouse pointer reports `pointer: fine`, which is what the hint keys on.
  ...(AS_DESKTOP ? ['--touch-events=disabled'] : []),
  '--remote-debugging-port=0',
  `http://127.0.0.1:${PORT}/index.html`,
], { stdio: 'ignore' })

const portFile = join(PROFILE, 'DevToolsActivePort')
let debugPort = 0
for (let i = 0; i < 100; i += 1) {
  await delay(200)
  if (fsCallback.existsSync(portFile)) {
    debugPort = Number(fsCallback.readFileSync(portFile, 'utf8').split('\n')[0])
    break
  }
}
const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json()
const page = targets.find((target) => target.type === 'page')
const socket = new WebSocket(page.webSocketDebuggerUrl, { perMessageDeflate: false })
await new Promise((resolve, reject) => {
  socket.once('open', resolve)
  socket.once('error', reject)
})

let nextId = 1
const pending = new Map()
socket.on('message', (raw) => {
  const message = JSON.parse(raw.toString())
  if (message.id && pending.has(message.id)) {
    pending.get(message.id)(message)
    pending.delete(message.id)
  }
  if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') {
    console.log(`[error] ${message.params.entry.text}`)
  }
})
function send(method, params = {}) {
  const id = nextId++
  socket.send(JSON.stringify({ id, method, params }))
  return new Promise((resolve) => pending.set(id, resolve))
}

await send('Runtime.enable')
await send('Page.enable')
await send('Log.enable')
// Device emulation: CSS viewport + DPR + touch, exactly what a phone reports.
// Skipped for the desktop run, which must see a fine pointer and no touch.
if (!AS_DESKTOP) {
  await send('Emulation.setDeviceMetricsOverride', {
    width: WIDTH,
    height: HEIGHT,
    deviceScaleFactor: 2,
    mobile: true,
    screenWidth: WIDTH,
    screenHeight: HEIGHT,
  })
  await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 })
}
await send('Page.reload', { ignoreCache: true })

let report = null
for (let i = 0; i < 60; i += 1) {
  await delay(1000)
  const probe = await send('Runtime.evaluate', {
    expression: `(() => {
      const c = document.querySelector('canvas');
      const cs = c ? getComputedStyle(c) : null;
      return JSON.stringify({
        inner: innerWidth + 'x' + innerHeight,
        visual: visualViewport ? Math.round(visualViewport.width) + 'x' + Math.round(visualViewport.height) : 'n/a',
        dpr: devicePixelRatio,
        canvasCss: c ? cs.width + 'x' + cs.height : 'none',
        canvasAttr: c ? c.width + 'x' + c.height : 'none',
        wrapper: (() => { const w = document.getElementById('game'); return w ? getComputedStyle(w).padding : 'sin wrapper'; })(),
        bodyBg: getComputedStyle(document.body).backgroundColor,
        scrollH: document.documentElement.scrollHeight,
        statusOverlay: !!document.getElementById('status'),
        // Rotate-hint state, plus the media queries that drive it.
        orientDisplay: (() => {
          const o = document.getElementById('orient');
          return o ? getComputedStyle(o).display : 'sin overlay';
        })(),
        mqPortrait: window.matchMedia('(orientation: portrait)').matches,
        mqCoarse: window.matchMedia('(pointer: coarse)').matches,
      });
    })()`,
    returnByValue: true,
  })
  const raw = probe.result?.result?.value
  if (!raw) continue
  report = JSON.parse(raw)
  const pixels = await send('Runtime.evaluate', {
    expression: `(() => {
      const c = document.querySelector('canvas');
      const gl = c.getContext('webgl2') || c.getContext('webgl');
      if (!gl) return 'no-gl';
      const read = (x, y) => { const p = new Uint8Array(4);
        gl.readPixels(x, y, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, p);
        return p[0] + ',' + p[1] + ',' + p[2]; };
      return read(20, 20) + ' | ' + read(c.width >> 1, c.height >> 1);
    })()`,
    returnByValue: true,
  })
  console.log(`  t=${i + 1}s canvas(css)=${report.canvasCss} canvas(buffer)=${report.canvasAttr} px=${pixels.result?.result?.value}`)
  if (report.canvasAttr !== 'none' && report.canvasAttr !== '0x0') break
}

console.log('--- informe ---')
for (const [key, value] of Object.entries(report ?? {})) console.log(`  ${key}: ${value}`)

const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false })
if (shot.result?.data) {
  // Give asynchronous work (the Firebase counters and leaderboard) a chance to
  // land before the picture is taken.
  const settle = Number(process.env.SETTLE_SECONDS ?? 0)
  if (settle > 0) {
    console.log(`esperando ${settle}s a que lleguen los contadores...`)
    await delay(settle * 1000)
  }
  // Optional: press at a fraction of the viewport, to catch the swat circle
  // while it is on screen (it fades out in about 0.28 s). With PRESS_AFTER=1 the
  // press happens after the settle delay instead of before, which is what a
  // press inside the running game needs.
  const press = process.env.PRESS_AT
  if (press) {
    await pressAt(press)
  }
  const final = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false })
  if (final.result?.data) {
    await writeFile(SHOT, Buffer.from(final.result.data, 'base64'))
  }
  // Report the canvas against the viewport again: after a scene change the two
  // can disagree, which shows up as a strip of page background on one side.
  const after = await send('Runtime.evaluate', {
    expression: `(() => {
      const c = document.querySelector('canvas');
      const w = document.getElementById('game');
      const r = c.getBoundingClientRect();
      const wr = w ? w.getBoundingClientRect() : null;
      const cs = getComputedStyle(c);
      return JSON.stringify({
        viewport: innerWidth + 'x' + innerHeight,
        canvasRect: [r.left, r.top, r.right, r.bottom].map(Math.round).join(','),
        canvasCss: cs.width + 'x' + cs.height,
        wrapperRect: wr ? [wr.left, wr.top, wr.right, wr.bottom].map(Math.round).join(',') : 'sin wrapper',
        wrapperPadding: w ? getComputedStyle(w).padding : '-',
        canvasBuffer: c.width + 'x' + c.height,
        dpr: devicePixelRatio,
      });
    })()`,
    returnByValue: true,
  })
  console.log('--- después del clic ---')
  const info = JSON.parse(after.result?.result?.value ?? '{}')
  for (const [key, value] of Object.entries(info)) console.log(`  ${key}: ${value}`)
  console.log(`screenshot -> ${SHOT}`)
}

async function pressAt(fraction) {
  const [fx, fy] = fraction.split(',').map(Number)
  const x = Math.round(WIDTH * fx)
  const y = Math.round(HEIGHT * fy)
  console.log(`pulsando en ${x},${y}`)
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none', clickCount: 0 })
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 })
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 })
  await delay(Number(process.env.PRESS_DELAY_MS ?? 60))
}

socket.close()
chrome.kill()
server.close()
process.exit(0)

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
