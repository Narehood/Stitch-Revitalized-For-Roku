'use strict';

const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

// Keep independent engine processes within a small pool without increasing
// fixture deadlines or overriding the smaller default on constrained hosts.
const concurrency = Math.min(4, Math.max(1, os.availableParallelism() - 1));
const cwd = path.resolve(__dirname, '..');
const files = fs.readdirSync(path.join(cwd, 'tools/tests'))
    .filter(file => file.endsWith('.test.js')).sort();
const isolated = 'roku-vod-chunks.test.js';
if (!files.includes(isolated)) throw new Error('Recorded chunk regression is missing');

// This binary-golden matrix approaches its finite child deadline on Windows
// when it competes with other engine processes. Run all its cases alone.
for (const [limit, batch] of [[1, [isolated]], [concurrency, files.filter(file => file !== isolated)]]) {
    if (batch.length === 0) continue;
    const result = spawnSync(process.execPath, [
        '--test', `--test-concurrency=${limit}`, ...batch.map(file => `tools/tests/${file}`)
    ], {cwd, stdio: 'inherit', windowsHide: true});
    if (result.error) process.stderr.write('Node regression runner could not start\n');
    const code = Number.isInteger(result.status) ? result.status : 1;
    if (code !== 0) {
        process.exitCode = code;
        break;
    }
}
