import type { Generator, RandomGenerator } from '../schemas/secrets'
import { randomBytes } from 'node:crypto'
import { compareSync, hashSync } from 'bcryptjs'

/** A generator that builds its value from another key of the manifest (its `input`) instead of from random bytes */
export type DerivedGenerator = Exclude<Generator, RandomGenerator>

export function isDerived(generator: Generator): generator is DerivedGenerator {
  return generator.type !== 'random'
}

export function generateRandom(generator: RandomGenerator): string {
  return generator.prefix + randomBytes(generator.bytes).toString(generator.encoding)
}

/** The value a derived generator builds from its input; a new generator type adds its case here and in isDerivedFrom */
export function derive(generator: DerivedGenerator, input: string): string {
  switch (generator.type) {
    case 'bcrypt':
      return hashSync(input, generator.rounds)
  }
}

/** Whether `value` is what the generator builds from `input`; a salted hash differs on every run, so equality cannot tell */
export function isDerivedFrom(generator: DerivedGenerator, input: string, value: string): boolean {
  switch (generator.type) {
    case 'bcrypt':
      return compareSync(input, value)
  }
}
