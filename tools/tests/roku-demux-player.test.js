'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');

const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/roku-demux-player');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const keyDriver = path.join(fixtures, 'key-driver.js');
const snapshotFiles = ['components/Scenes/VideoPlayer/VideoPlayer.brs',
    'components/Scenes/VideoPlayer/VideoPlayer.xml', 'components/Scenes/VideoPlayer/RokuPlayback.brs',
    'components/heroScene.brs', 'components/heroScene.xml'];

async function snapshot() {
    return Promise.all(snapshotFiles.map(async file => [file,
        createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex')]));
}

async function addFile(dir, file, data) {
    const target = path.join(dir, file);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, data);
}

async function copyFile(dir, file) {
    await addFile(dir, file, await fs.readFile(path.join(root, file)));
}

async function copyTree(dir, folder) {
    for (const entry of await fs.readdir(path.join(root, folder), { withFileTypes: true })) {
        const file = `${folder}/${entry.name}`;
        if (entry.isDirectory()) await copyTree(dir, file);
        else await copyFile(dir, file);
    }
}

async function fixture(name) {
    return fs.readFile(path.join(fixtures, name), 'utf8');
}

async function buildPackage(dir, marker, mode = 'normal') {
    await addFile(dir, 'manifest', 'title=Roku Player Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/analytics.brs', 'source/utils/uiContrast.brs']) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/CirclePoster',
        'components/SceneManager/Group', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoErrorHandler', 'components/Modules/StitchVideo',
        'components/Modules/CustomVideo']) await copyTree(dir, folder);
    for (const file of ['Chat.xml', 'Chat.brs']) await copyFile(dir, `components/Modules/Chat/${file}`);
    // Actual EmojiLabel rendering code; pattern construction is an explicit
    // existing engine boundary. Transport/bookmarks/registry never start.
    for (const file of ['EmojiLabel.xml', 'EmojiLabel.brs', 'EmojiLabelUtil.brs']) await copyFile(dir, `components/Modules/EmojiLabel/${file}`);
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fixture('EmojiLabelRegex.brs'));
    await addFile(dir, 'source/utils/config.brs', await fixture('config.brs'));
    for (const file of ['RokuPlayerHost.xml', 'SessionBoundary.xml', 'SessionBoundary.brs',
        'GetTwitchContent.xml', 'GetTwitchContentBoundary.brs', 'TwitchApiTask.xml',
        'RW_AddTask.xml', 'ChatJob.xml', 'EmoteJob.xml']) await addFile(dir, `components/${file}`, await fixture(file));
    const probe = await fixture('PlayerProbe.brs');
    const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
        .map(match => `<function name="${match[1]}" />`).join('');
    assert.ok(exports, 'read-only inspection exports missing');
    const originalXml = await fs.readFile(path.join(root, snapshotFiles[1]), 'utf8');
    const xml = originalXml.replace('</interface>', `${exports}</interface>`)
        .replace('</component>', '<script uri="pkg:/components/PlayerProbe.brs" /></component>');
    await addFile(dir, snapshotFiles[1], xml);
    await addFile(dir, 'components/PlayerProbe.brs', probe);
    for (const file of [snapshotFiles[0], snapshotFiles[2]]) {
        await copyFile(dir, file);
        assert.deepEqual(await fs.readFile(path.join(dir, file)), await fs.readFile(path.join(root, file)), `${file} must execute unchanged`);
    }
    let main = await fixture('main.brs');
    if (mode === 'failed-assertion') {
        assert.ok(main.includes('check(true, "failure-control anchor")'));
        main = main.replace('check(true, "failure-control anchor")', 'check(false, "deliberate wrong assertion")');
    }
    await addFile(dir, 'source/main.brs', main);
    const summaryMarker = mode === 'stale-marker' ? `STITCH_UI_PASS:${randomUUID()}` : marker;
    await addFile(dir, 'source/support.brs', (await fixture('support.brs')).replaceAll('__PASS_MARKER__', summaryMarker));
}

function runChild(command, args, cwd, timeoutMs = 60000, outputLimit = 1024 * 1024) {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '';
        let bytes = 0;
        let exceeded = false;
        let timedOut = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > outputLimit) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.on('error', error => { clearTimeout(timer); reject(error); });
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded });
        });
    });
}

function acceptResult(result, marker) {
    const failure = result.output.slice(-16000);
    assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
    assert.equal(result.exceeded, false, `fixture exceeded output limit\n${failure}`);
    assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
    // brs-node cannot assign these native ContentNode fields; all production
    // scripts still execute unchanged. Do not claim their array storage or
    // hardware behavior. Every other engine error remains a failure.
    const supportedOutput = result.output.replace(/^BRIGHTSCRIPT: ERROR: roSGNode\.AddReplace: "TwitchContentNode\.(?:streams|streamqualities)": Type mismatch! pkg:.*TwitchContentNode\.brs\(\d+\)\r?\n/gm, '');
    assert.doesNotMatch(supportedOutput, /BRIGHTSCRIPT: ERROR:/, failure);
    assert.doesNotMatch(result.output, /STITCH_UI_FAIL:|FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|unhandled exception/i, failure);
    assert.match(result.output, /EXIT_USER_NAV/, `fixture did not close normally\n${failure}`);
    const summaries = [...result.output.matchAll(/STITCH_UI_PASS:[0-9a-f-]+:\s*(\d+) assertions/g)];
    assert.equal(summaries.length, 1, `expected exactly one summary\n${failure}`);
    const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
    assert.ok(summary, `fresh success marker missing\n${failure}`);
    assert.ok(Number(summary[1]) > 0, `zero actual assertions\n${failure}`);
    return Number(summary[1]);
}

async function runFixture(mode = 'normal') {
    const prefix = 'stitch-roku-player-';
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    const before = await snapshot();
    try {
        const dir = path.join(temp, 'package');
        await buildPackage(dir, marker, mode);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(dir, zip);
        const result = await runChild(process.execPath, [keyDriver, cli, zip], temp);
        assert.deepEqual(await snapshot(), before, 'the production snapshot changed while the fixture ran');
        return { result, marker };
    } finally {
        const resolved = path.resolve(temp);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('actual player callbacks gate Roku opt-in, session ready, retry, quality switch, Back and disposal', { timeout: 90000 }, async t => {
    const { result, marker } = await runFixture();
    const count = acceptResult(result, marker);
    t.diagnostic(`${count} actual SceneGraph assertions; Session and network are explicit inert IO boundaries; no decoder/hardware proof`);
});

test('a genuine failed BrightScript assertion and a stale success marker are rejected', { timeout: 180000 }, async () => {
    const failed = await runFixture('failed-assertion');
    assert.equal(failed.result.code, 0, 'engine may exit normally despite a test assertion failure');
    assert.match(failed.result.output, /STITCH_UI_FAIL:deliberate wrong assertion/);
    assert.throws(() => acceptResult(failed.result, failed.marker));
    const stale = await runFixture('stale-marker');
    assert.equal(stale.result.code, 0);
    assert.match(stale.result.output, /STITCH_UI_PASS:[0-9a-f-]+:\s*[1-9]\d* assertions/);
    assert.throws(() => acceptResult(stale.result, stale.marker), /fresh success marker missing/);
});

test('bounded child transport rejects failure output, timeout, overflow and nonzero exit', { timeout: 15000 }, async () => {
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    const valid = `${marker}: 1 assertions\nEXIT_USER_NAV\n`;
    const child = script => runChild(process.execPath, ['-e', script], os.tmpdir(), 2000, 1024);
    const badOutput = await child(`process.stdout.write(${JSON.stringify(valid + 'STITCH_UI_FAIL: deliberate\n')});`);
    assert.throws(() => acceptResult(badOutput, marker));
    const timeout = await runChild(process.execPath, ['-e', 'setInterval(() => {}, 100);'], os.tmpdir(), 150, 1024);
    assert.equal(timeout.timedOut, true);
    assert.throws(() => acceptResult(timeout, marker), /timed out/);
    const overflow = await child('process.stdout.write("x".repeat(2048));');
    assert.equal(overflow.exceeded, true);
    assert.throws(() => acceptResult(overflow, marker), /output limit/);
    const nonzero = await child(`process.stdout.write(${JSON.stringify(valid)}); process.exitCode = 7;`);
    assert.equal(nonzero.code, 7);
    assert.throws(() => acceptResult(nonzero, marker), /exited 7/);
});
