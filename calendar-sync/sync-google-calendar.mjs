#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { projectCanonicalSchedule } from './schedule-projection.mjs';
import { synchronizeCalendarProjection } from './calendar-reconciliation.mjs';
import { createGoogleCalendarAdapter, readWriteConfiguration } from './google-calendar-adapter.mjs';

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.dirname(moduleDirectory);

function parseArguments(argv) {
  let mode = 'dry-run';
  let schedulePath = 'data/schedule.json';
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === '--write') mode = 'write';
    else if (value === '--dry-run') mode = 'dry-run';
    else if (value === '--schedule' && argv[index + 1]) schedulePath = argv[++index];
    else throw new Error(`Unknown calendar sync argument: ${value}.`);
  }
  return { mode, schedulePath };
}

function emptyReadAdapter() {
  return {
    async listEvents() { return []; },
    async createEvent() { throw new Error('Dry-run attempted a create write.'); },
    async updateEvent() { throw new Error('Dry-run attempted an update write.'); },
    async deleteEvent() { throw new Error('Dry-run attempted a delete write.'); }
  };
}

export async function runCalendarSync({ repoRoot = defaultRepoRoot, argv = process.argv.slice(2), env = process.env, adapterFactory = createGoogleCalendarAdapter } = {}) {
  const options = parseArguments(argv);
  const raw = JSON.parse(await fs.readFile(path.resolve(repoRoot, options.schedulePath), 'utf8'));
  const projection = await projectCanonicalSchedule({ repoRoot, schedule: raw });

  let adapter;
  if (options.mode === 'write') {
    const configuration = readWriteConfiguration(env);
    adapter = await adapterFactory(configuration);
  } else {
    adapter = emptyReadAdapter();
  }

  const result = await synchronizeCalendarProjection({
    desiredEvents: projection.events,
    adapter,
    dryRun: options.mode !== 'write'
  });
  return {
    scheduleVersion: projection.schedule.scheduleVersion,
    desired: result.desired,
    created: result.created,
    updated: result.updated,
    deleted: result.deleted,
    unchanged: result.unchanged
  };
}

async function main() {
  try {
    const summary = await runCalendarSync();
    console.log(JSON.stringify(summary, null, 2));
  } catch (error) {
    console.error(`Calendar sync failed: ${error instanceof Error ? error.message : 'Unknown error.'}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
