#!/usr/bin/env node

/**
 * Stop hook: Ensure learning directories exist
 * Learning extraction is handled by prompt hook in settings.json
 */

import { existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

const CONFIG = {
  cacheLearningsPath: join(homedir(), '.claude', 'cache', 'learnings'),
  rulesLearningsPath: join(homedir(), '.claude', 'rules', 'learnings'),
};

function ensureDirectories() {
  const dirs = [
    CONFIG.cacheLearningsPath,
    join(CONFIG.cacheLearningsPath, 'general'),
    CONFIG.rulesLearningsPath,
  ];

  for (const dir of dirs) {
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
      console.error(`[Learning] Created: ${dir}`);
    }
  }
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf-8');
}

async function main() {
  try {
    const input = await readStdin();
    if (!input.trim()) {
      ensureDirectories();
      return;
    }

    const hookData = JSON.parse(input);

    // Avoid infinite loops
    if (hookData.stop_hook_active) {
      return;
    }

    ensureDirectories();

  } catch (error) {
    console.error(`[Learning] Warning: ${error.message}`);
  }
}

main();
