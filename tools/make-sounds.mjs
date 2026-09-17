// Generates the game's sound effects as real WAV files (16-bit mono PCM),
// synthesised sample by sample so the project needs no external audio assets.
import { mkdirSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'

const RATE = 22050

function chunk(id, data) {
  const header = Buffer.alloc(8)
  header.write(id, 0, 'latin1')
  header.writeUInt32LE(data.length, 4)
  return Buffer.concat([header, data])
}

function encodeWAV(samples) {
  const data = Buffer.alloc(samples.length * 2)
  for (let i = 0; i < samples.length; i += 1) {
    const value = Math.max(-1, Math.min(1, samples[i]))
    data.writeInt16LE(Math.round(value * 32767), i * 2)
  }
  const fmt = Buffer.alloc(16)
  fmt.writeUInt16LE(1, 0) // PCM
  fmt.writeUInt16LE(1, 2) // mono
  fmt.writeUInt32LE(RATE, 4)
  fmt.writeUInt32LE(RATE * 2, 8) // byte rate
  fmt.writeUInt16LE(2, 12) // block align
  fmt.writeUInt16LE(16, 14) // bits per sample
  const header = Buffer.alloc(12)
  header.write('RIFF', 0, 'latin1')
  header.writeUInt32LE(36 + data.length, 4)
  header.write('WAVE', 8, 'latin1')
  return Buffer.concat([header, chunk('fmt ', fmt), chunk('data', data)])
}

function lowpassNoise(length, cutoff) {
  const out = new Float64Array(length)
  const rc = 1 / (2 * Math.PI * cutoff)
  const dt = 1 / RATE
  const alpha = dt / (rc + dt)
  let previous = 0
  for (let i = 0; i < length; i += 1) {
    const white = Math.random() * 2 - 1
    previous += alpha * (white - previous)
    out[i] = previous
  }
  return out
}

function clamp01(v) {
  return v < 0 ? 0 : v > 1 ? 1 : v
}

// One swat: a body thump that drops in pitch, a wet broadband splat, then a
// short tail of small ticks so it reads as something being crushed.
function squish() {
  const duration = 0.36
  const length = Math.floor(RATE * duration)
  const out = new Float64Array(length)
  const wet = lowpassNoise(length, 1800)
  const hiss = lowpassNoise(length, 5200)

  let phase = 0
  for (let i = 0; i < length; i += 1) {
    const t = i / RATE

    // Body: 190 Hz sweeping down to 45 Hz.
    const frequency = 190 * Math.exp(-t * 9) + 45
    phase += (2 * Math.PI * frequency) / RATE
    const bodyEnv = Math.exp(-t * 16) * (1 - Math.exp(-t * 700))
    const body = Math.sin(phase) * bodyEnv * 0.85

    // Wet splat: bursts of filtered noise with a fast attack and short decay.
    const burst = Math.exp(-Math.pow((t - 0.012) * 34, 2))
    const wetEnv = burst * Math.exp(-t * 11)
    const splat = wet[i] * wetEnv * 2.4

    // Fine splatter ticks around 20 ms.
    const tick = hiss[i] * Math.exp(-Math.pow((t - 0.02) * 260, 2)) * 0.5

    let value = body + splat + tick
    // Soft clip so the sum never crackles.
    value = Math.tanh(value * 1.25) * 0.92
    // Fade the very end to zero so there is no click.
    const tail = t > duration - 0.03 ? clamp01((duration - t) / 0.03) : 1
    out[i] = value * tail
  }
  return out
}

const outputDir = join(process.cwd(), 'assets', 'audio')
mkdirSync(outputDir, { recursive: true })
writeFileSync(join(outputDir, 'squish.wav'), encodeWAV(squish()))
process.stdout.write(`generated squish.wav in ${outputDir}\n`)
