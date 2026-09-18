// Throwaway web test: taps a LineEdit inside the exported build, exactly like a
// finger would, and reports whether the keystrokes reach Godot.
//
// It answers three questions in order, and prints the DOM state in between:
//   1. does the tap land on a DOM input the user can type into?
//   2. does the engine's LineEdit receive the characters?
//   3. does the value survive, and is the engine object the same one?
//
//   node tools/web-typing-check.mjs <port> <shot.png>
import { createServer } from 'node:http'
import { writeFile } from 'node:fs/promises'
import { join, extname } from 'node:path'
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
import * as fsCallback from 'node:fs'
import { promisify } from 'node:util'

const PORT = Number(process.argv[2] ?? 8170)
const SHOT = process.argv[3] ?? 'E:\\software\\juegos\\mataCudos\\build\\typing.png'
const ROOT = 'E:\\software\\juegos\\mataCudos\\build\\web'
const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
const PROFILE = `${process.env.TEMP}\\dsh-chrome-typing`
const WIDTH = 844
const HEIGHT = 390

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
  } catch {
    response.writeHead(404).end('not found')
  }
})
await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve))

const chrome = spawn(CHROME, [
  '--headless=new', '--disable-gpu', '--enable-unsafe-swiftshader',
  '--use-gl=angle', '--use-angle=swiftshader',
  `--window-size=${WIDTH},${HEIGHT}`, `--user-data-dir=${PROFILE}`,
  '--no-first-run', '--disable-extensions',
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
  '--remote-debugging-port=0', `http://127.0.0.1:${PORT}/index.html`,
], { stdio: 'inherit' })

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
const page = targets.find((t) => t.type === 'page')
const socket = new WebSocket(page.webSocketDebuggerUrl, { perMessageDeflate: false })
await new Promise((resolve, reject) => { socket.once('open', resolve); socket.once('error', reject) })

let nextId = 1
const pending = new Map()
socket.on('message', (raw) => {
  const message = JSON.parse(raw.toString())
  if (message.id && pending.has(message.id)) { pending.get(message.id)(message); pending.delete(message.id) }
  if (message.method === 'Runtime.consoleAPICalled') {
    const text = (message.params.args ?? []).map((a) => a.value ?? a.description ?? '').join(' ')
    // Everything the page logs, so the engine's own diagnostics are visible.
    console.log(`  [juego] ${text}`)
  }
})
function send(method, params = {}) {
  const id = nextId++
  socket.send(JSON.stringify({ id, method, params }))
  return new Promise((resolve) => pending.set(id, resolve))
}
const evaluate = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true })
  return r.result?.result?.value
}

await send('Runtime.enable')
await send('Page.enable')
await send('Log.enable')
await send('Emulation.setDeviceMetricsOverride', {
  width: WIDTH, height: HEIGHT, deviceScaleFactor: 2, mobile: true,
  screenWidth: WIDTH, screenHeight: HEIGHT,
})
// Chrome's own touch points are not trusted input, so each touch is sent twice:
// once as a mouse event (which Godot's emulation turns into a ScreenTouch) and
// once as a real CDP touch, so the page behaves exactly as it does on a phone.
await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 })
await send('Page.reload', { ignoreCache: true })

// Wait until the engine is drawing the probe scene.
for (let i = 0; i < 40; i += 1) {
  await delay(1000)
  const drawn = await evaluate(`(() => {
    const c = document.querySelector('canvas');
    const gl = c && (c.getContext('webgl2') || c.getContext('webgl'));
    if (!gl) return false;
    const p = new Uint8Array(4);
    gl.readPixels(4, 4, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, p);
    return p[0] + p[1] + p[2] > 20;
  })()`)
  if (drawn) { console.log(`motor dibujando tras ${i + 1}s`); break }
}

// In game mode: start a run and wait for it to end on its own, which is the
// state the player types in. Tapping the middle of the screen also presses the
// COMENZAR button on the menu.
const GAME = process.env.GAME === '1'
if (GAME) {
  console.log('--- arrancando una partida ---')
  await tap(Math.round(WIDTH / 2), Math.round(HEIGHT / 2))
  // The run ends by itself once the window fills up (about 40-60 s). Poll the
  // screenshot for the dark panel instead of waiting a fixed time.
  let ended = false
  for (let i = 0; i < 90; i += 1) {
    await delay(2000)
    const dark = await evaluate(`(() => {
      const c = document.querySelector('canvas');
      const gl = c.getContext('webgl2') || c.getContext('webgl');
      const p = new Uint8Array(4);
      gl.readPixels(Math.round(c.width * 0.5), Math.round(c.height * 0.25), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, p);
      return p[0] + ',' + p[1] + ',' + p[2];
    })()`)
    if (i % 5 === 0) console.log(`  t=${(i + 1) * 2}s centro-arriba=${dark}`)
    // The panel is dark blue (~5,8,13); the window is light (~200,220,232).
    const [r, g, b] = String(dark).split(',').map(Number)
    if (r < 40 && g < 40 && b < 60) { ended = true; break }
  }
  console.log(`¿terminó la partida? ${ended}`)
  const shot0 = await send('Page.captureScreenshot', { format: 'png' })
  if (shot0.result?.data) {
    await writeFile(SHOT.replace(/\.png$/, '-gameover.png'), Buffer.from(shot0.result.data, 'base64'))
    console.log(`screenshot del fin de partida -> ${SHOT.replace(/\.png$/, '-gameover.png')}`)
  }
}

console.log('--- antes de tocar ---')
console.log('  activeElement:', await evaluate('document.activeElement ? document.activeElement.tagName : "null"'))
console.log('  inputs en el DOM:', await evaluate('document.querySelectorAll("input,textarea").length'))

// Tap the field: in design space it is at (430..850, 20..110), and 1 unit is
// 844/1280 px on this screen.
const scale = WIDTH / 1280
const x = Math.round(640 * scale)
const y = Math.round(65 * scale)
console.log(`--- tocando el campo en ${x},${y} ---`)
await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none', clickCount: 0 })
await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 })
await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 })
await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] })
await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
await delay(500)

console.log('--- despues de tocar ---')
console.log('  activeElement:', await evaluate('document.activeElement ? document.activeElement.tagName + " value=" + JSON.stringify(document.activeElement.value ?? "") : "null"'))
console.log('  inputs en el DOM:', await evaluate('document.querySelectorAll("input,textarea").length'))
console.log('  seleccion/candidatos:', await evaluate(`(() => {
  const a = document.activeElement;
  return a ? (a.type || a.tagName) + " inputmode=" + (a.inputMode ?? "") + " readonly=" + (a.readOnly ?? "") : "sin foco";
})()`))

console.log('--- escribiendo "Zancu" ---')
for (const ch of 'Zancu') {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', text: ch, unmodifiedText: ch, key: ch })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: ch })
  await delay(120)
}
await delay(1500)
console.log('  activeElement.value:', await evaluate('document.activeElement ? JSON.stringify(document.activeElement.value ?? "") : "null"'))
console.log('  (los mensajes [juego] de arriba dicen que recibio el LineEdit)')

const shot = await send('Page.captureScreenshot', { format: 'png' })
if (shot.result?.data) {
  await writeFile(SHOT, Buffer.from(shot.result.data, 'base64'))
  console.log(`screenshot -> ${SHOT}`)
}

socket.close()
chrome.kill()
server.close()
process.exit(0)

function delay(ms) { return new Promise((resolve) => setTimeout(resolve, ms)) }

// One tap: mouse (which Godot's emulation turns into a ScreenTouch) plus a real
// CDP touch, so the page behaves exactly as it does under a finger.
async function tap(x, y) {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none', clickCount: 0 })
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 })
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 })
  await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] })
  await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
}
