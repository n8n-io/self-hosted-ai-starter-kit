import { expect, test } from 'vitest'
import { keyValue } from '../src/utils/format'

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

test('keyValue highlights the key in cyan when colours are on and stays plain when they are off', () => {
  withColours(true, () => expect(keyValue('KEY', 'value')).toBe('\u001B[36mKEY\u001B[39m=value'))
  withColours(false, () => expect(keyValue('KEY', '')).toBe('KEY='))
})
