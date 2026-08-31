#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readWriteConfiguration } from '../calendar-sync/google-calendar-adapter.mjs';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function main() {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const cases = [];

  async function test(name, run) {
    try {
      await run();
      cases.push({ name, ok: true });
    } catch (error) {
      cases.push({ name, ok: false, error: error instanceof Error ? error.message : String(error) });
    }
  }

  await test('ADC/WIF configuration does not require a service-account JSON key', async () => {
    const configuration = readWriteConfiguration({
      GOOGLE_APPLICATION_CREDENTIALS: '/tmp/gha-creds-test.json',
      LC_GOOGLE_CALENDAR_PROCEDURES_ID: 'procedures-id',
      LC_GOOGLE_CALENDAR_MEALS_ID: 'meals-id'
    });
    assert(configuration.authMode === 'application-default', 'ADC auth mode was not selected.');
    assert(configuration.credentials === null, 'ADC mode unexpectedly contains long-lived credentials.');
    assert(configuration.calendarIds.Procedury === 'procedures-id', 'Procedury calendar ID was not preserved.');
    assert(configuration.calendarIds['Jídlo'] === 'meals-id', 'Jídlo calendar ID was not preserved.');
  });

  await test('write mode still fails closed when no authentication is present', async () => {
    let failed = false;
    try {
      readWriteConfiguration({
        LC_GOOGLE_CALENDAR_PROCEDURES_ID: 'procedures-id',
        LC_GOOGLE_CALENDAR_MEALS_ID: 'meals-id'
      });
    } catch (error) {
      failed = /GOOGLE_APPLICATION_CREDENTIALS/.test(error.message) && /LC_GOOGLE_SERVICE_ACCOUNT_JSON/.test(error.message);
    }
    assert(failed, 'Missing authentication did not fail closed.');
  });

  await test('production workflow uses GitHub OIDC and no service-account secret', async () => {
    const workflow = await fs.readFile(path.join(repoRoot, '.github/workflows/google-calendar-sync.yml'), 'utf8');
    assert(workflow.includes('id-token: write'), 'OIDC id-token permission is missing.');
    assert(workflow.includes('google-github-actions/auth@v3'), 'Google OIDC auth action is missing.');
    assert(workflow.includes('projects/217549425263/locations/global/workloadIdentityPools/github-actions/providers/github-actions'), 'Expected WIF provider is missing.');
    assert(workflow.includes('lazensky-commander-calendar-sy@lazensky-commander.iam.gserviceaccount.com'), 'Expected service account is missing.');
    assert(!workflow.includes('secrets.LC_GOOGLE_SERVICE_ACCOUNT_JSON'), 'Workflow still references the long-lived JSON secret.');
  });

  await test('production workflow keeps Google write restricted to main', async () => {
    const workflow = await fs.readFile(path.join(repoRoot, '.github/workflows/google-calendar-sync.yml'), 'utf8');
    assert(workflow.includes("if: github.ref == 'refs/heads/main'"), 'Main-only write guard is missing.');
    assert(workflow.includes('branches:\n      - main'), 'Push trigger is not restricted to main.');
  });

  await test('workflow validates dry-run before obtaining Google credentials', async () => {
    const workflow = await fs.readFile(path.join(repoRoot, '.github/workflows/google-calendar-sync.yml'), 'utf8');
    const dryRunIndex = workflow.indexOf('Validate canonical schedule and build dry-run plan');
    const authIndex = workflow.indexOf('Authenticate to Google Cloud with GitHub OIDC');
    const writeIndex = workflow.indexOf('Reconcile Google Calendars');
    assert(dryRunIndex >= 0 && authIndex > dryRunIndex && writeIndex > authIndex, 'Workflow ordering is not dry-run -> OIDC auth -> write.');
  });

  const failed = cases.filter(item => !item.ok);
  console.log(JSON.stringify({ passed: cases.length - failed.length, failed: failed.length, cases }, null, 2));
  if (failed.length) process.exitCode = 1;
}

await main();
