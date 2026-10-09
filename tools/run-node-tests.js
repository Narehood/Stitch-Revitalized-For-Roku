'use strict';

const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

// Keep independent engine processes within a small pool without increasing
// fixture deadlines or overriding the smaller default on constrained hosts.
const concurrency = Math.min(4, Math.max(1, os.availableParallelism() - 1));
const result = spawnSync(process.execPath, [
    '--test', `--test-concurrency=${concurrency}`, 'tools/tests/*.test.js'
], {cwd: path.resolve(__dirname, '..'), stdio: 'inherit', windowsHide: true});

if (result.error) process.stderr.write('Node regression runner could not start\n');
process.exitCode = Number.isInteger(result.status) ? result.status : 1;
