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

// A checkout that does not declare these fails here with a bare module
// resolution stack trace, which reads as a broken script rather than an
// incomplete checkout. Name the package and the consequence instead.
const requireOrExplain = (moduleName: string): unknown => {
  try {
    return require(moduleName);
  } catch (e) {
    if ((e as NodeJS.ErrnoException | undefined)?.code === 'MODULE_NOT_FOUND') {
      console.error(`[grep-filter] '${ moduleName }' is not installed in this checkout.`);
      console.error('[grep-filter] Spec pre-selection needs it, so tag filtering cannot run.');
      console.error('[grep-filter] It is installed from cypress/yarn.lock, so the checkout has');
      console.error('[grep-filter] to declare it. release-2.14 and newer do.');
      process.exit(1);
    }
    throw e;
  }
};

const globby = requireOrExplain('globby') as { sync: (patterns: string[], opts: { cwd: string; ignore: string[]; absolute: boolean }) => string[] };
const { getTestNames } = requireOrExplain('find-test-names') as { getTestNames: (text: string) => { tests: Array<{ tags: string[] }> } };

// Resolve utils.js dynamically relative to the main entrypoint to bypass exports encapsulation in v6
let parseGrep: (title: string | null, tags: string) => unknown;
let shouldTestRun: (parsed: unknown, title: string | null, tags: string[]) => boolean;

// Only a genuinely absent module justifies the legacy fallback. Any other error
// is a real fault inside @cypress/grep and must surface as itself, rather than
// being retried and reported as a misleading module-resolution failure.
const isModuleResolutionError = (e: unknown): boolean => {
  const code = (e as NodeJS.ErrnoException | undefined)?.code;

  return code === 'MODULE_NOT_FOUND' || code === 'ERR_PACKAGE_PATH_NOT_EXPORTED';
};

try {
  const grepMain = require.resolve('@cypress/grep');
  const grepUtilsPath = path.join(path.dirname(grepMain), 'utils.js');
  ({ parseGrep, shouldTestRun } = require(grepUtilsPath) as {
    parseGrep: (title: string | null, tags: string) => unknown;
    shouldTestRun: (parsed: unknown, title: string | null, tags: string[]) => boolean;
  });
} catch (e) {
  if (!isModuleResolutionError(e)) {
    throw e;
  }

  // Fallback to legacy path for older branches using @cypress/grep v3/v4
  ({ parseGrep, shouldTestRun } = require('@cypress/grep/src/utils') as {
    parseGrep: (title: string | null, tags: string) => unknown;
    shouldTestRun: (parsed: unknown, title: string | null, tags: string[]) => boolean;
  });
}

const grepTags: string | undefined = process.env.CYPRESS_grepTags || process.env.GREP_TAGS;

if (!grepTags) {
  // No tags specified, so run all specs (output nothing so cypress.sh skips --spec)
  process.exit(0);
}

const testSkip: string = process.env.TEST_SKIP || '';
const skipSetup: boolean = testSkip.includes('setup') || process.env.TEST_SKIP_SETUP === 'true';

// IMPORTANT: keep in sync with testDirs in cypress.config.jenkins.ts
const testDirs: string[] = [
  'cypress/e2e/tests/priority/**/*.spec.ts',
  'cypress/e2e/tests/components/**/*.spec.ts',
  ...(skipSetup ? [] : ['cypress/e2e/tests/setup/**/*.spec.ts']),
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
    console.error('grep-filter: could not parse %s, including it', specFile);

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
