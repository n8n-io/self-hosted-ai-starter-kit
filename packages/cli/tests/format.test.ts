import { expect, test } from 'vitest'
import { ACCENT, accent, keyValue } from '../src/utils/format'

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

test('accent writes the brand pink as far as the colour depth allows and stays plain when colours are off', () => {
  expect(ACCENT).toBe('#FF91AC')
  withColours(true, () => {
    expect(accent('n8n', 24)).toBe('\u001B[38;2;255;145;172mn8n\u001B[39m')
    expect(accent('n8n', 8)).toBe('\u001B[38;5;211mn8n\u001B[39m')
    expect(accent('n8n', 4)).toBe('\u001B[95mn8n\u001B[39m')
    // no tty in a test run: the depth of a forced colour run
    expect(accent('n8n')).toBe('\u001B[95mn8n\u001B[39m')
  })
  withColours(false, () => {
    expect(accent('n8n', 24)).toBe('n8n')
    expect(accent('n8n')).toBe('n8n')
  })
})

test('keyValue highlights the key in the accent colour when colours are on and stays plain when they are off', () => {
  withColours(true, () => expect(keyValue('KEY', 'value')).toBe('\u001B[95mKEY\u001B[39m=value'))
  withColours(false, () => expect(keyValue('KEY', '')).toBe('KEY='))
})
