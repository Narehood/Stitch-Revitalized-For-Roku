'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('actual EventSub raid validation and worker publication reject stale, incoming, duplicate and wrong-owner events', () => {
    const root = path.resolve(__dirname, '../..');
    const worker = fs.readFileSync(path.join(root, 'components/Tasks/RaidWatchTask/RaidWatchTask.brs'), 'utf8');
    let functions = ['raidWatchCurrent', 'publishRaidFrame', 'openRaidSocket', 'closeRaidSockets', 'runRaidWatch', 'subscribeRaid', 'runRaidSession'].map(name => {
        const match = worker.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)\\r?$`, 'm'));
        assert.ok(match, `actual worker ${name} missing`);
        return match[0];
    }).join('\n');
    // Only native event/socket/HTTP/wait boundaries are replaced in this
    // temporary script. All subscription, migration and publication code runs.
    functions = functions.replaceAll('wait(', 'raidFixtureWait(')
        .replaceAll('type(event)', 'raidFixtureType(event)')
        .replaceAll('CreateObject(componentType)', 'raidFixtureSocket()')
        .replaceAll('CreateObject("roUrlTransfer")', 'raidFixtureTransfer()');
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'stitch-raid-protocol-'));
    try {
        const file = path.join(temp, 'worker.brs');
        fs.writeFileSync(file, functions);
        const result = spawnSync(process.execPath, [
            path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg',
            'source/utils/raidEvents.brs', 'tools/tests/fixtures/raids/protocol.brs', file,
        ], { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 15000, maxBuffer: 256 * 1024 });
        assert.ifError(result.error);
        const output = `${result.stdout}\n${result.stderr}`;
        assert.equal(result.status, 0, output);
        assert.match(output, /RAID_PROTOCOL_PASS:\s*49/, output);
        assert.doesNotMatch(output, /RAID_PROTOCOL_FAIL|EXIT_BRIGHTSCRIPT_CRASH|runtime error/i);
    } finally {
        fs.rmSync(temp, { recursive: true, force: true });
    }
});
