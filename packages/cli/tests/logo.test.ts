import { stripVTControlCharacters } from 'node:util'
import { expect, test } from 'vitest'
import { LOGO_MARK, LOGO_WIDTH, LOGO_WORDMARK, nextSteps, READY, renderBanner } from '../src/utils/logo'

/** Runs `fn` with the colour variables set as given and restores them afterwards */
function withColours(forced: boolean, fn: () => void) {
  const previous = { FORCE_COLOR: process.env.FORCE_COLOR, NO_COLOR: process.env.NO_COLOR }
  try {
    // FORCE_COLOR wins over NO_COLOR and the missing tty, see util.styleText
    if (forced) {
      process.env.FORCE_COLOR = '1'
      delete process.env.NO_COLOR
    } else {
      delete process.env.FORCE_COLOR
      process.env.NO_COLOR = '1'
    }
    fn()
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined)
        delete process.env[key]
      else
        process.env[key] = value
    }
  }
}

test('the logo is five rows of half blocks within 60 columns, the mark a block of 30', () => {
  expect(LOGO_MARK).toHaveLength(5)
  expect(LOGO_WORDMARK).toHaveLength(5)
  expect(new Set(LOGO_MARK.map(row => row.length))).toEqual(new Set([30]))
  expect(Math.max(...LOGO_WORDMARK.map(row => row.length))).toBe(30)
  expect(LOGO_WIDTH).toBe(63)
  for (const row of [...LOGO_MARK, ...LOGO_WORDMARK])
    expect(row).toMatch(/^[ ▀▄█]+$/)
})

test('renderBanner ends with the ready line and the next steps under the logo and stays plain when colours are off', () => {
  expect(READY).toBe('self-hosted-ai-starter-kit ready to use')
  withColours(false, () => {
    const lines = renderBanner(undefined)
    expect(nextSteps()).toBe('Next: pnpm run dev starts the stack, pnpm run config changes its settings')
    expect(lines).toEqual([...LOGO_MARK.map((mark, row) => `   ${mark}${LOGO_WORDMARK[row]}`), '', `   ${READY}`, `   ${nextSteps()}`])
    expect(lines.join('\n')).not.toMatch(/\u001B\[/)
    expect(renderBanner(LOGO_WIDTH)).toEqual(lines)
  })
})

test('renderBanner colours the mark in the accent colour and leaves the wordmark to the terminal', () => {
  withColours(true, () => {
    const lines = renderBanner(120)
    for (const [row, mark] of LOGO_MARK.entries())
      expect(lines[row]).toBe(`   \u001B[95m${mark}\u001B[39m${LOGO_WORDMARK[row]}`)
    // the commands of the last line carry the accent colour, the words between them stay plain
    expect(lines.at(-1)).toBe('   Next: \u001B[95mpnpm run dev\u001B[39m starts the stack, \u001B[95mpnpm run config\u001B[39m changes its settings')
    expect(lines.at(-2)).toBe(`   ${READY}`)
    // the codes add no width: without them the rows are the plain logo
    expect(lines.slice(0, 5).map(line => stripVTControlCharacters(line))).toEqual(LOGO_MARK.map((mark, row) => `   ${mark}${LOGO_WORDMARK[row]}`))
  })
})

test('renderBanner drops the logo in a terminal too narrow for it', () => {
  expect(renderBanner(LOGO_WIDTH - 1)).toEqual([`   ${READY}`, `   ${nextSteps()}`])
  expect(renderBanner(40)).toEqual([`   ${READY}`, `   ${nextSteps()}`])
  // a pty without a size reports 0 columns: unknown, not narrow
  expect(renderBanner(0)).toHaveLength(8)
})
