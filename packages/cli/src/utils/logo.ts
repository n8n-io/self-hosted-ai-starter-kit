import { accent } from './format'

/**
 * The n8n logo in half blocks, 60 columns by 5 rows: the paths of the n8n logo SVG
 * (a pink #FF91AC mark and the wordmark, in black or white) rasterised once at 60 by 10 pixels, a pixel set
 * from 30 % coverage.
 * The mark takes the first 30 columns, the wordmark starts at column 39 like in the SVG.
 */
export const LOGO_MARK = [
  '     ██       ██       ██     ',
  '     ██       ██       ██     ',
  '██████████████████████████████',
  '     ██       ██       ██     ',
  '     ██       ██       ██     ',
] as const

export const LOGO_WORDMARK = [
  '                 ▄▄▄▄▄',
  '         ▄▄▄▄▄  ██▀ ▀██ ▄▄▄▄▄',
  '         ██▀▀██  █████  ██▀▀██',
  '         ██  ██ ██▄ ▄██ ██  ██',
  '         ▀▀  ▀▀  ▀▀▀▀▀  ▀▀  ▀▀',
] as const

/** The closing line of a setup that went through */
export const READY = 'self-hosted-ai-starter-kit ready to use'

/**
 * The line under it: what to run next, through the root scripts like every hint. The commands are in the accent
 * colour instead of backticks, so they read as plain text where colours are off.
 */
export function nextSteps(): string {
  return `Next: ${accent('pnpm run dev')} starts the stack, ${accent('pnpm run config')} changes its settings`
}

/** The indent of the text of a clack outro, which the banner follows */
const INDENT = '   '

/** The columns the logo needs, indent included */
export const LOGO_WIDTH = INDENT.length + Math.max(...LOGO_MARK.map((mark, row) => mark.length + LOGO_WORDMARK[row]!.length))

/**
 * The lines `setup` signs off with: the logo with the mark in the accent colour and the wordmark in the
 * foreground of the terminal (the two SVGs are that pair for a light and a dark background), an empty line, the
 * ready line and the next steps with their commands in the accent colour. A terminal narrower than the logo gets the two lines alone, since wrapped rows
 * are no logo; a width that is not known (no tty, or a pty that reports 0 columns) gets the logo.
 */
export function renderBanner(columns: number | undefined = process.stdout.columns): string[] {
  const closing = [`${INDENT}${READY}`, `${INDENT}${nextSteps()}`]
  if (columns !== undefined && columns > 0 && columns < LOGO_WIDTH)
    return closing
  return [
    ...LOGO_MARK.map((mark, row) => `${INDENT}${accent(mark)}${LOGO_WORDMARK[row]}`),
    '',
    ...closing,
  ]
}
