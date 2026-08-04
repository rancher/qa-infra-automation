/* eslint-disable no-console */
import { defineConfig } from 'cypress';
import { removeDirectory } from 'cypress-delete-downloads-folder';
import websocketTasks from '../../cypress/support/utils/webSocket-utils';
import path from 'path';

// Required for env vars to be available in cypress
require('dotenv').config();

/**
 * VARIABLES
 */

const testDirs = [
  'cypress/e2e/tests/priority/**/*.spec.ts',
  'cypress/e2e/tests/components/**/*.spec.ts',
  'cypress/e2e/tests/setup/**/*.spec.ts',
  'cypress/e2e/tests/pages/**/*.spec.ts',
  'cypress/e2e/tests/navigation/**/*.spec.ts',
  'cypress/e2e/tests/global-ui/**/*.spec.ts',
  'cypress/e2e/tests/features/**/*.spec.ts',
  'cypress/e2e/tests/extensions/**/*.spec.ts'
];
const skipSetup = process.env.TEST_SKIP?.includes('setup');
const baseUrl = (process.env.TEST_BASE_URL || 'https://localhost:8005').replace(/\/$/, '');
const DEFAULT_USERNAME = 'admin';
const username = process.env.TEST_USERNAME || DEFAULT_USERNAME;
const apiUrl = process.env.API || (baseUrl.endsWith('/dashboard') ? baseUrl.split('/').slice(0, -1).join('/') : baseUrl);

/**
 * LOGS:
 * Summary of the environment variables that we have detected (or are going ot use)
 * We won't show any passwords
 */
console.log('E2E Test Configuration');
console.log('');
console.log(`    Username: ${ username }`);

if (!process.env.CATTLE_BOOTSTRAP_PASSWORD && !process.env.TEST_PASSWORD) {
  console.log(' ❌ You must provide either CATTLE_BOOTSTRAP_PASSWORD or TEST_PASSWORD');
}
if (process.env.CATTLE_BOOTSTRAP_PASSWORD && process.env.TEST_PASSWORD) {
  console.log(' ❗ If both CATTLE_BOOTSTRAP_PASSWORD and TEST_PASSWORD are provided, the first will be used');
}
if (!skipSetup && !process.env.CATTLE_BOOTSTRAP_PASSWORD) {
  console.log(' ❌ You must provide CATTLE_BOOTSTRAP_PASSWORD when running setup tests');
}
if (skipSetup && !process.env.TEST_PASSWORD) {
  console.log(' ❌ You must provide TEST_PASSWORD when running the tests without the setup tests');
}

console.log(`    Setup tests will ${ skipSetup ? 'NOT' : '' } be run`);
console.log(`    Dashboard URL: ${ baseUrl }`);
console.log(`    Rancher API URL: ${ apiUrl }`);

// Check API - sometimes in dev, you might have API set to a different system to the base url - this won't work
// as the login cookie will be for the base url and any API requests will fail as not authenticated
if (apiUrl && !baseUrl.startsWith(apiUrl)) {
  console.log('\n ❗ API variable is different to TEST_BASE_URL - tests may fail due to authentication issues');
}

// The reporter chain is resolved by name at runtime, so a missing package is a
// hard failure inside Cypress rather than a build error here.
// `cypress-multi-reporters`, `mocha-junit-reporter` and `cypress-qase-reporter`
// only exist in the dashboard master dependency set. Clone runs overlay master's
// manifests onto release branches and therefore always have them. A
// `--dashboard-dir` run keeps the local checkout's own manifest, so a release
// branch checkout has only `cypress-mochawesome-reporter`. Degrade to that
// rather than failing the run.
const canResolve = (moduleName: string): boolean => {
  try {
    require.resolve(moduleName);

    return true;
  } catch {
    return false;
  }
};

const multiReporters = canResolve('cypress-multi-reporters') && canResolve('mocha-junit-reporter');

if (!multiReporters) {
  console.log('Reporters: cypress-multi-reporters or mocha-junit-reporter is not installed. Falling back to cypress-mochawesome-reporter. No JUnit XML will be produced.');
}

// @cypress/grep v5+ reads its settings through the Cypress 15 `Cypress.expose`
// API and ignores `env` entirely, so tags placed in `env` silently disable all
// test level filtering. Cypress 11 rejects an unknown top level `expose` key,
// so pick the one the installed pair understands. The v5+ layout exposes
// `@cypress/grep/plugin`; v3/v4 only ship `src/plugin`.
const grepSettings = {
  grepFilterSpecs:  false,
  grepOmitFiltered: true,
  // Note: grepTags is fully calculated in the cypress.sh entrypoint
  grepTags:         process.env.CYPRESS_grepTags || process.env.GREP_TAGS
};
const grepUsesExpose = canResolve('@cypress/grep/plugin');

console.log(`Grep: passing filter settings through '${ grepUsesExpose ? 'expose' : 'env' }' (tags: ${ grepSettings.grepTags || 'none' })`);

// Conditionally enable Qase reporter only if reporting is requested AND a token is present
const qaseRequested = (process.env.QASE_REPORT === 'true' || process.env.qase_report === 'true') && !!(process.env.QASE_AUTOMATION_TOKEN || process.env.qase_automation_token);
const qaseEnabled = qaseRequested && multiReporters && canResolve('cypress-qase-reporter');

if (qaseRequested && !qaseEnabled) {
  console.log('Qase: Reporting was requested but the reporter chain is unavailable in this checkout. Qase reporting is disabled for this run.');
} else if (qaseEnabled) {
  console.log('Qase: Reporting enabled. Automation token is defined.');
}

const multiReporterOptions = {
  reporterEnabled:                   `cypress-mochawesome-reporter, mocha-junit-reporter${ qaseEnabled ? ', cypress-qase-reporter' : '' }`,
  mochaJunitReporterReporterOptions: {
    mochaFile:      'cypress/jenkins/reports/junit/junit-[hash].xml',
    toConsole:      false,
    jenkinsMode:    true,
    includePending: true
  },
  cypressMochawesomeReporterReporterOptions: { charts: false },
  cypressQaseReporterReporterOptions:        {
    mode:    qaseEnabled ? 'testops' : 'off',
    debug:   process.env.QASE_DEBUG === 'true',
    testops: {
      api:               { token: process.env.QASE_AUTOMATION_TOKEN || process.env.qase_automation_token },
      project:           process.env.QASE_PROJECT || process.env.qase_project || 'SANDBOX',
      uploadAttachments: true,
      run:               {
        title:       `UI E2E - ${ process.env.RANCHER_IMAGE_TAG || 'unknown' } - ${ process.env.CYPRESS_grepTags || 'none' } - ${ new Date().toISOString().replace('T', ' ').replace(/\.\d+Z$/, ' UTC') }`,
        description: `Rancher Version: ${ process.env.RANCHER_VERSION || 'unknown' } | Tags: ${ process.env.CYPRESS_grepTags || 'none' }`,
        complete:    true
      }
    },
    framework: { cypress: { screenshotsFolder: 'cypress/screenshots' } }
  }
};

console.log('');

/**
 * CONFIGURATION
 */
export default defineConfig({
  ...(grepUsesExpose ? { expose: grepSettings } : {}),
  projectId:             process.env.TEST_PROJECT_ID,
  defaultCommandTimeout: process.env.TEST_TIMEOUT ? +process.env.TEST_TIMEOUT : 10000,
  trashAssetsBeforeRuns: false,
  chromeWebSecurity:     false,
  retries:               {
    runMode:  2,
    openMode: 0
  },
  env: {
    ...(grepUsesExpose ? {} : grepSettings),
    baseUrl,
    api:                 apiUrl,
    username,
    password:            process.env.CATTLE_BOOTSTRAP_PASSWORD || process.env.TEST_PASSWORD,
    bootstrapPassword:   process.env.CATTLE_BOOTSTRAP_PASSWORD,
    // the below env vars are only available to tests that run in Jenkins
    awsAccessKey:        process.env.AWS_ACCESS_KEY_ID,
    awsSecretKey:        process.env.AWS_SECRET_ACCESS_KEY,
    azureSubscriptionId: process.env.AZURE_AKS_SUBSCRIPTION_ID,
    azureClientId:       process.env.AZURE_CLIENT_ID,
    azureClientSecret:   process.env.AZURE_CLIENT_SECRET,
    customNodeIp:        process.env.CUSTOM_NODE_IP,
    customNodeKey:       process.env.CUSTOM_NODE_KEY,
    customNodeUser:      process.env.CUSTOM_NODE_USER || 'ec2-user',
    accessibility:       !!process.env.TEST_A11Y, // Are we running accessibility tests?
    a11yFolder:          path.join('.', 'cypress', 'accessibility'),
    gkeServiceAccount:   process.env.GKE_SERVICE_ACCOUNT,
    // Skip chart tests when the chart is filtered out of the UI catalog (default). Set to false to fail instead.
    allowFilteredCatalogSkip: process.env.CYPRESS_ALLOW_FILTERED_CATALOG_SKIP !== 'false',
  },
  // Jenkins reporters configuration jUnit and HTML
  reporter:        multiReporters ? 'cypress-multi-reporters' : 'cypress-mochawesome-reporter',
  reporterOptions: multiReporters ? multiReporterOptions : { charts: false },
  e2e: {
    setupNodeEvents(on, config) {
      try {
        // v5/v6 entrypoint
        require('@cypress/grep/plugin').plugin(config);
      } catch (e) {
        // Only a genuinely absent module justifies the legacy fallback. Any
        // other error is a real fault inside the plugin and must surface as
        // itself, rather than being retried and reported as a misleading
        // module-resolution failure.
        const code = (e as NodeJS.ErrnoException)?.code;

        if (code !== 'MODULE_NOT_FOUND' && code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') {
          throw e;
        }

        // Legacy v3/v4 entrypoint
        require('@cypress/grep/src/plugin')(config);
      }

      const mochawesome = require('cypress-mochawesome-reporter/lib');

      on('before:run', async(details: Cypress.BeforeRunDetails) => {
        await mochawesome.beforeRunHook(details);
        if (qaseEnabled) {
          const { beforeRunHook } = require('cypress-qase-reporter/hooks');

          await beforeRunHook(config);
        }
      });

      if (qaseEnabled) {
        const { afterSpecHook } = require('cypress-qase-reporter/hooks');
        const fs = require('fs');
        const qaseResultsPath = require.resolve('cypress-qase-reporter/hooks').replace('hooks.js', 'metadata/qaseResults');

        on('after:spec', async(spec: Cypress.Spec) => {
          // Filter out results without a Qase ID to avoid creating unlinked test cases
          if (fs.existsSync(qaseResultsPath)) {
            try {
              const results = JSON.parse(fs.readFileSync(qaseResultsPath, 'utf8'));
              // eslint-disable-next-line camelcase
              const filtered = results.filter((r: { testops_id: number | number[] | null }) => r.testops_id !== null && r.testops_id !== undefined);

              console.log(`[Qase] ${ spec.name }: ${ results.length } result(s), ${ filtered.length } with Qase ID${ filtered.length ? ` (${ filtered.map((r: { testops_id: number }) => r.testops_id).join(', ') })` : '' }`);
              fs.writeFileSync(qaseResultsPath, JSON.stringify(filtered));
            } catch (e) {
              console.error('Error filtering Qase results:', e);
            }
          } else {
            console.log(`[Qase] ${ spec.name }: no results file found`);
          }

          // afterSpecHook reads filtered results, uploads to Qase API, then clears the file
          // It also handles video file matching using spec.name when video: true
          await afterSpecHook(spec, config);
        });
      }

      on('after:run', async(results: { totalTests?: number }) => {
        // Report generation must never decide the outcome of a run.
        // cypress-mochawesome-reporter 3.8.2, the version release branches pin,
        // throws `RangeError: Invalid array length` when no test matched the
        // grep tags, which turns an empty selection into a failed run.
        if (results && results.totalTests === 0) {
          console.log('Reporters: no tests ran, skipping report generation. Check that the grep tags match tests in the selected spec files.');
        } else {
          try {
            await mochawesome.afterRunHook();
          } catch (e) {
            console.error('Reporters: mochawesome report generation failed, continuing without an HTML report:', e);
          }
        }
        if (qaseEnabled) {
          const { afterRunHook } = require('cypress-qase-reporter/hooks');

          await afterRunHook(config);
        }
      });

      // Load Accessibility plugin if configured
      if (process.env.TEST_A11Y) {
        require('../../cypress/support/plugins/accessibility').default(on, config);
      }

      on('task', { removeDirectory });
      websocketTasks(on, config);

      require('cypress-terminal-report/src/installLogsPrinter')(on, {
        outputRoot:           `${ config.projectRoot }/browser-logs/`,
        outputTarget:         { 'out.html': 'html' },
        // Disabled in Jenkins config only to prevent conflict with cypress-mochawesome-reporter's after:run hook
        // Both plugins use after:run; this prevents Cypress from exiting before HTML reports are generated
        logToFilesOnAfterRun: false,
        printLogsToConsole:   'never',
        // printLogsToFile:      'always', // default prints on failures
      });

      return config;
    },
    fixturesFolder:               'cypress/e2e/blueprints',
    // Cypress 11 will not accept a suite level testIsolation without this,
    // and Cypress 12 removed it, so 15 prints a removal notice on every run.
    // grep v5+ resolving means the checkout is on Cypress 15.
    ...(grepUsesExpose ? {} : { experimentalSessionAndOrigin: true }),
    specPattern:                  testDirs,
    baseUrl
  },
  video:               false,
  videoCompression:    25,
  videoUploadOnPasses: false,
});
