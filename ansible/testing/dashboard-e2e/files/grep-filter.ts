/**
 * Pre-filter script for @cypress/grep tag matching.
 *
 * Resolves spec files from testDirs glob patterns, AST-parses each file
 * for tags using find-test-names, then applies the same shouldTestRun
 * logic that @cypress/grep uses internally.
 *
 * Outputs a comma-separated list of matching spec file paths (relative)
 * to stdout. If no grepTags are set or no specs match, outputs nothing.
 *
 * Usage:
 *   CYPRESS_grepTags="@adminUser" node --experimental-strip-types cypress/jenkins/grep-filter.ts
 */

/* eslint-disable no-console, @typescript-eslint/no-require-imports */

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

const globby = require('globby') as { sync: (patterns: string[], opts: { cwd: string; ignore: string[]; absolute: boolean }) => string[] };
const { getTestNames } = require('find-test-names') as { getTestNames: (text: string) => { tests: Array<{ tags: string[] }> } };
const { parseGrep, shouldTestRun } = require('@cypress/grep/src/utils') as {
  parseGrep: (title: string | null, tags: string) => unknown;
  shouldTestRun: (parsed: unknown, title: string | null, tags: string[]) => boolean;
};

const grepTags: string | undefined = process.env.CYPRESS_grepTags || process.env.GREP_TAGS;

if (!grepTags) {
  // No tags specified — run all specs (output nothing so cypress.sh skips --spec)
  process.exit(0);
}

// IMPORTANT: keep in sync with testDirs in cypress.config.jenkins.ts
const testDirs: string[] = [
  'cypress/e2e/tests/priority/**/*.spec.ts',
  'cypress/e2e/tests/components/**/*.spec.ts',
  'cypress/e2e/tests/setup/**/*.spec.ts',
  'cypress/e2e/tests/pages/**/*.spec.ts',
  'cypress/e2e/tests/navigation/**/*.spec.ts',
  'cypress/e2e/tests/global-ui/**/*.spec.ts',
  'cypress/e2e/tests/features/**/*.spec.ts',
  'cypress/e2e/tests/extensions/**/*.spec.ts',
];

const cwd: string = process.cwd();

const specFiles: string[] = globby.sync(testDirs, {
  cwd,
  ignore:   ['*.hot-update.js'],
  absolute: true,
});

const parsedGrep = parseGrep(null, grepTags);

const matched: string[] = specFiles.filter((specFile: string) => {
  try {
    const text = fs.readFileSync(specFile, { encoding: 'utf8' });
    const testInfo = getTestNames(text);

    return testInfo.tests.some((info) => shouldTestRun(parsedGrep, null, info.tags));
  } catch {
    // If we can't parse it, include it so Cypress can handle it at runtime
    console.error('grep-filter: could not parse %s — including it', specFile);

    return true;
  }
});

if (matched.length === 0) {
  console.error('grep-filter: no specs matched tag(s) "%s"', grepTags);
  process.exit(0);
}

console.error('grep-filter: matched %d spec(s) for tag(s) "%s"', matched.length, grepTags);

// Output relative paths, comma-separated (Cypress --spec format)
const relativePaths: string[] = matched.map((p) => path.relative(cwd, p));

process.stdout.write(relativePaths.join(','));
