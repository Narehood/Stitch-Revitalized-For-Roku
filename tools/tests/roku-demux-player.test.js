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
    'components/heroScene.brs', 'components/heroScene.xml',
    'components/Modules/StitchVideo/StitchVideo.brs', 'components/Modules/StitchVideo/StitchVideo.xml',
    'components/Modules/VideoErrorHandler/VideoErrorHandler.brs'];

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
        'source/utils/analytics.brs', 'source/utils/uiContrast.brs',
        'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs']) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/CirclePoster',
        'components/SceneManager/Group', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoErrorHandler', 'components/Modules/StitchVideo',
        'components/Modules/CustomVideo', 'components/Modules/AdCountdown']) await copyTree(dir, folder);
    for (const file of ['Chat.xml', 'Chat.brs']) await copyFile(dir, `components/Modules/Chat/${file}`);
    // Actual EmojiLabel rendering code; pattern construction is an explicit
    // existing engine boundary. Transport/bookmarks/registry never start.
    for (const file of ['EmojiLabel.xml', 'EmojiLabel.brs', 'EmojiLabelUtil.brs']) await copyFile(dir, `components/Modules/EmojiLabel/${file}`);
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fixture('EmojiLabelRegex.brs'));
    await addFile(dir, 'source/utils/config.brs', await fixture('config.brs'));
    for (const file of ['RokuPlayerHost.xml', 'SessionBoundary.xml', 'SessionBoundary.brs',
        'GetTwitchContent.xml', 'GetTwitchContentBoundary.brs', 'TwitchApiTask.xml',
        'RW_AddTask.xml', 'ChatJob.xml', 'EmoteJob.xml']) await addFile(dir, `components/${file}`, await fixture(file));
    await addFile(dir, 'components/DialogKeyBoundary.xml', '<component name="DialogKeyBoundary" extends="Group"><interface><field id="pressCount" type="integer" /></interface><script uri="DialogKeyBoundary.brs" /></component>');
    await addFile(dir, 'components/DialogKeyBoundary.brs', 'function onKeyEvent(key as string, press as boolean) as boolean\n    if LCase(key) = "ok" and press then m.top.pressCount++\n    return true\nend function\n');
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
    // Control only the watchdog's native wall-clock read; its health/stall
    // handlers and all other production bodies remain byte-identical.
    const playerPath = snapshotFiles[0];
    const actualPlayer = await fs.readFile(path.join(dir, playerPath), 'utf8');
    const watchdog = /sub onWatchdogFire\(\)[\s\S]*?end sub/;
    const watchdogSource = actualPlayer.match(watchdog)?.[0];
    const nativeClock = 'nowSec = CreateObject("roDateTime").AsSeconds()';
    assert.equal(watchdogSource?.split(nativeClock).length, 2, 'one actual watchdog clock read required');
    const controlledWatchdog = watchdogSource.replace(nativeClock, 'nowSec = fixtureWatchdogClock()');
    assert.equal(controlledWatchdog.replace('nowSec = fixtureWatchdogClock()', nativeClock), watchdogSource);
    await addFile(dir, playerPath, actualPlayer.replace(watchdog, controlledWatchdog));
    if (mode === 'old-buffer-downgrade' || mode === 'old-error-downgrade') {
        const buffer = mode === 'old-buffer-downgrade';
        const name = buffer ? 'findLowerQuality' : 'getNextLowerQuality';
        const file = buffer ? snapshotFiles[0] : 'components/Modules/VideoErrorHandler/VideoErrorHandler.brs';
        const script = await fs.readFile(path.join(dir, file), 'utf8');
        const pattern = new RegExp(`^function ${name}\\([^]*?^end function`, 'gm');
        assert.equal([...script.matchAll(pattern)].length, 1, `one actual ${name} helper required`);
        await addFile(dir, file, script.replace(pattern, (await fixture(`${name}.before.brs`)).trimEnd()));
    }
    if (mode === 'old-quality-flag') {
        const file = 'components/Modules/StitchVideo/StitchVideo.xml';
        const xml = await fs.readFile(path.join(dir, file), 'utf8');
        const field = '<field id="QualityChangeRequestFlag" type="bool" value="false" alwaysNotify="true" />';
        assert.equal(xml.split(field).length, 2, 'one current quality flag required');
        await addFile(dir, file, xml.replace(field, '<field id="QualityChangeRequestFlag" type="bool" value="false" />'));
    }
    if (mode === 'old-quality-flag' || mode === 'no-quality-flag-reset') {
        const file = snapshotFiles[0];
        const script = await fs.readFile(path.join(dir, file), 'utf8');
        const reset = '    if m.video.isSubtype("StitchVideo") then m.video.QualityChangeRequestFlag = false';
        assert.equal(script.split(reset).length, 2, 'one current quality consumption reset required');
        await addFile(dir, file, script.replace(reset, ''));
    }
    if (mode === 'no-source-transition-recovery') {
        const file = snapshotFiles[2];
        const script = await fs.readFile(path.join(dir, file), 'utf8');
        const gate = '        if sourceTransition';
        assert.equal(script.split(gate).length, 2, 'one actual transition dispatch gate required');
        await addFile(dir, file, script.replace(gate, '        if false'));
    }
    if (mode === 'no-source-transition-retry-guard') {
        const file = snapshotFiles[2];
        const script = await fs.readFile(path.join(dir, file), 'utf8');
        const guard = '            if m.retryTimer <> invalid or m.reconnectTimer <> invalid or m.reconnectTask <> invalid then return';
        assert.equal(script.split(guard).length, 2, 'one actual pending-retry transition guard required');
        await addFile(dir, file, script.replace(guard, '            if m.reconnectTimer <> invalid or m.reconnectTask <> invalid then return'));
    }
    const healthMutations = {
        'health-time': ['nowSec - m.liveRecoveryStartSec < 120', 'nowSec - m.liveRecoveryStartSec < 0'],
        'health-media': [' or position - m.liveRecoveryStartPosition < 90', ''],
        'health-blanket': ['    m.recoveryAttempts -= charges', '    m.recoveryAttempts = 0'],
        'health-state': ['    if m.video.state <> "playing" then resetLiveRecoveryHealth()', ''],
        'health-gap': ['elapsed < 0 or elapsed > 6 or progress <= 0', 'elapsed < 0 or progress <= 0']
    };
    if (healthMutations[mode]) {
        const [before, after] = healthMutations[mode];
        const script = await fs.readFile(path.join(dir, playerPath), 'utf8');
        assert.equal(script.split(before).length, 2, `one current ${mode} health guard required`);
        await addFile(dir, playerPath, script.replace(before, after));
    }
    if (mode === 'lost-manual-live-quality') {
        const script = await fs.readFile(path.join(dir, playerPath), 'utf8');
        const guard = '        if m.top.contentRequested.contentType = "LIVE" and m.manualLiveQuality <> invalid then quality = m.manualLiveQuality';
        assert.equal(script.split(guard).length, 2, 'one actual remembered manual LIVE quality match required');
        await addFile(dir, playerPath, script.replace(guard, ''));
    }
    let main = await fixture('main.brs');
    if (['repeated-dialog', 'fixed-dialog-wait', 'dropped-dialog'].includes(mode)) {
        const start = main.match(/sub main\(\)[\s\S]*?end sub/)?.[0];
        assert.ok(start?.includes('    testLiveManualQualityIntent()'));
        const setup = start.split(/\r?\n/).filter(line => !/^\s+test/.test(line)).join('\n');
        main = main.replace(start, setup.replace('    try', '    try\n        testRepeatedDialogDispatch()'));
        if (mode === 'fixed-dialog-wait') {
            const wait = /    dispatch = createObject\("roTimespan"\)\r?\n    while player\.callFunc\("fixtureRead"\)\.transmuxDialog <> invalid and dispatch\.totalMilliseconds\(\) < 2000\r?\n        pump\(20\)\r?\n    end while/;
            assert.equal([...main.matchAll(new RegExp(wait.source, 'g'))].length, 1, 'one actual bounded dialog dispatch wait required');
            main = main.replace(wait, '    settle(160)');
        }
    } else if (['repeated-retry', 'fixed-retry-wait', 'dropped-retry'].includes(mode)) {
        const start = main.match(/sub main\(\)[\s\S]*?end sub/)?.[0];
        assert.ok(start?.includes('    testFailedRetryAndRecovery()'));
        const retryOnly = start.split(/\r?\n/).filter(line => !/^\s+test/.test(line) || line.trim() === 'testFailedRetryAndRecovery()').join('\n');
        main = main.replace(start, retryOnly);
        if (mode === 'fixed-retry-wait') {
            const wait = /    dispatch = createObject\("roTimespan"\)\r?\n    while player\.callFunc\("fixtureRead"\)\.task = invalid and dispatch\.totalMilliseconds\(\) < 2000\r?\n        pump\(20\)\r?\n    end while/;
            assert.equal([...main.matchAll(new RegExp(wait.source, 'g'))].length, 1, 'one actual bounded manual retry wait required');
            main = main.replace(wait, '    settle(160)');
        }
    } else if (mode === 'failed-assertion' || mode === 'stale-marker') {
        const start = main.match(/sub main\(\)[\s\S]*?end sub/)?.[0];
        assert.ok(start?.includes('    testChoiceReadyAndBack()'));
        // Summary controls need a genuine player lifecycle, not every unrelated
        // quality/recovery matrix. The normal run still executes that matrix.
        const summaryOnly = start.split(/\r?\n/).filter(line => !/^\s+test/.test(line)
            || line.trim() === 'testChoiceReadyAndBack()').join('\n');
        main = main.replace(start, summaryOnly);
    } else if (mode === 'manual-live-quality' || mode === 'lost-manual-live-quality') {
        const start = main.match(/sub main\(\)[\s\S]*?end sub/)?.[0];
        assert.ok(start?.includes('    testLiveManualQualityIntent()'));
        const qualityOnly = start.split(/\r?\n/).filter(line => !/^\s+test/.test(line) || line.trim() === 'testLiveManualQualityIntent()').join('\n');
        main = main.replace(start, qualityOnly);
    } else if (healthMutations[mode]) {
        const start = main.match(/sub main\(\)[\s\S]*?end sub/)?.[0];
        assert.ok(start?.includes('    testLiveRecoveryHealth()'));
        const healthOnly = start.split(/\r?\n/).filter(line => !/^\s+test/.test(line) || line.trim() === 'testLiveRecoveryHealth()').join('\n');
        main = main.replace(start, healthOnly);
        // Normal covers every interruption. Each mutation needs only its
        // specific behavior plus the actual mixed-budget/cap paths.
        const selectedCases = { 'health-time': [], 'health-media': ['noise'],
            'health-blanket': [], 'health-state': ['pause'], 'health-gap': ['gap'] };
        const cases = /    for each mode in \["stalled", "noise", "pause", "buffer"[^\r\n]+/;
        assert.equal([...main.matchAll(new RegExp(cases.source, 'g'))].length, 1, 'one current health interruption matrix required');
        main = main.replace(cases, `    for each mode in ${JSON.stringify(selectedCases[mode])}`);
    } else if (mode !== 'normal') {
        assert.equal(main.split('    testLiveRecoveryHealth()').length, 2);
        main = main.replace('    testLiveRecoveryHealth()', '');
    }
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
        const started = Date.now();
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
            resolve({ code, signal, output, timedOut, exceeded, elapsedMs: Date.now() - started });
        });
    });
}

function childDiagnostic(result, context = 'fixture') {
    return `${context}: code=${result.code} signal=${result.signal} timedOut=${result.timedOut} exceeded=${result.exceeded} elapsedMs=${result.elapsedMs}\n${result.output.slice(-16000)}`;
}

function assertNormalExit(result, context = 'fixture') {
    const failure = childDiagnostic(result, context);
    assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
    assert.equal(result.exceeded, false, `fixture exceeded output limit\n${failure}`);
    assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
    // brs-node cannot assign these native ContentNode fields; all production
    // scripts still execute unchanged. Do not claim their array storage or
    // hardware behavior. Every other engine error remains a failure.
    const supportedOutput = result.output.replace(/^BRIGHTSCRIPT: ERROR: roSGNode\.AddReplace: "TwitchContentNode\.(?:streams|streamqualities)": Type mismatch! pkg:.*TwitchContentNode\.brs\(\d+\)\r?\n/gm, '');
    assert.doesNotMatch(supportedOutput, /BRIGHTSCRIPT: ERROR:/, failure);
    assert.doesNotMatch(result.output, /FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|unhandled exception/i, failure);
    assert.match(result.output, /EXIT_USER_NAV/, `fixture did not close normally\n${failure}`);
}

function acceptResult(result, marker) {
    assertNormalExit(result);
    const failure = childDiagnostic(result);
    assert.doesNotMatch(result.output, /STITCH_UI_FAIL:/, failure);
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
        let driver = keyDriver;
        if (['repeated-dialog', 'fixed-dialog-wait', 'dropped-dialog', 'repeated-retry', 'fixed-retry-wait', 'dropped-retry'].includes(mode)) {
            let script = await fs.readFile(keyDriver, 'utf8');
            const gap = 'const repeatGapMs = 250;';
            assert.equal(script.split(gap).length, 2);
            script = script.replace(gap, 'const repeatGapMs = 600;');
            const schedule = 'nextFree = start + hold;';
            assert.equal(script.split(schedule).length, 2);
            script = script.replace(schedule, 'if (key === lastKey && start === nextFree + repeatGapMs) process.stderr.write("FIXTURE_REPEAT_QUEUED\\n");\n    ' + schedule);
            if (mode === 'dropped-dialog' || mode === 'dropped-retry') {
                const emit = "process.stdin.emit('keypress', '', { name, ctrl: false, meta: false, shift: false, sequence: '' });";
                assert.equal(script.split(emit).length, 2);
                script = script.replace('function emit(name) {', 'let emittedKeys = 0;\nfunction emit(name) {')
                    .replace(emit, 'if (++emittedKeys > 1) return;\n    ' + emit);
            }
            driver = path.join(temp, 'controlled-key-driver.js');
            await fs.writeFile(driver, script);
        }
        const result = await runChild(process.execPath, [driver, cli, zip], temp);
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

test('manual LIVE quality intent survives a missing recovery rung and rejects genuine intent loss', { timeout: 150000 }, async t => {
    const actual = await runFixture('manual-live-quality');
    t.diagnostic(`${acceptResult(actual.result, actual.marker)} actual manual-intent assertions with existing callbacks; no network/native playback claim`);
    const lost = await runFixture('lost-manual-live-quality');
    assertNormalExit(lost.result, 'lost-manual-live-quality');
    assert.match(lost.result.output, /STITCH_UI_FAIL:restored ladder returns to explicit manual quality/);
    assert.throws(() => acceptResult(lost.result, lost.marker));
    t.diagnostic('actual remembered manual-quality matching removal fails normally and is rejected');
});

test('actual repeated OK dispatch waits for its dialog and a missed deadline exits safely', { timeout: 180000 }, async t => {
    const actual = await runFixture('repeated-dialog');
    assert.match(actual.result.output, /FIXTURE_REPEAT_QUEUED/);
    t.diagnostic(`${acceptResult(actual.result, actual.marker)} actual assertions after the nextFree + repeatGapMs branch queues repeated OK`);
    for (const mode of ['fixed-dialog-wait', 'dropped-dialog']) {
        const failed = await runFixture(mode);
        assertNormalExit(failed.result, mode);
        assert.match(failed.result.output, /FIXTURE_REPEAT_QUEUED/);
        assert.match(failed.result.output, /STITCH_UI_FAIL:the actual remote choice closes its owned combined-format dialog/);
        assert.match(failed.result.output, /STITCH_UI_FAIL:\s*1 failures;\s*[1-9]\d* assertions/);
        assert.throws(() => acceptResult(failed.result, failed.marker));
        t.diagnostic(`${mode}: one real dispatch failure closes normally without continuing into a missing Video`);
    }
});

test('a genuine failed BrightScript assertion and a stale success marker are rejected', { timeout: 180000 }, async () => {
    const failed = await runFixture('failed-assertion');
    assertNormalExit(failed.result, 'failed-assertion');
    assert.match(failed.result.output, /STITCH_UI_FAIL:deliberate wrong assertion/);
    assert.match(failed.result.output, /STITCH_UI_FAIL:\s*1 failures;\s*[1-9]\d* assertions/, childDiagnostic(failed.result, 'failed-assertion'));
    assert.throws(() => acceptResult(failed.result, failed.marker));
    const stale = await runFixture('stale-marker');
    assertNormalExit(stale.result, 'stale-marker');
    assert.doesNotMatch(stale.result.output, /STITCH_UI_FAIL:/, childDiagnostic(stale.result, 'stale-marker'));
    assert.match(stale.result.output, /STITCH_UI_PASS:[0-9a-f-]+:\s*[1-9]\d* assertions/, childDiagnostic(stale.result, 'stale-marker'));
    assert.throws(() => acceptResult(stale.result, stale.marker), /fresh success marker missing/);
});

test('actual repeated Try again waits for its request and a missing retry key fails safely', { timeout: 180000 }, async t => {
    const actual = await runFixture('repeated-retry');
    assert.match(actual.result.output, /FIXTURE_REPEAT_QUEUED/);
    t.diagnostic(`${acceptResult(actual.result, actual.marker)} actual retry/session assertions after queued repeated OK`);
    for (const mode of ['fixed-retry-wait', 'dropped-retry']) {
        const failed = await runFixture(mode);
        assertNormalExit(failed.result, mode);
        assert.match(failed.result.output, /FIXTURE_REPEAT_QUEUED/);
        assert.match(failed.result.output, /STITCH_UI_FAIL:manual retry requests one fresh LIVE descriptor/);
        assert.match(failed.result.output, /STITCH_UI_FAIL:\s*1 failures;\s*[1-9]\d* assertions/);
        assert.throws(() => acceptResult(failed.result, failed.marker));
        t.diagnostic(`${mode}: exactly one actual retry failure closes normally without forcing the callback`);
    }
});

test('actual recovery and retained-wrapper selections reject historical quality defects and a missing consumption reset', { timeout: 270000 }, async t => {
    const cases = [
        ['old-buffer-downgrade', 'buffer recovery never promotes Automatic to the highest rung'],
        ['old-error-downgrade', 'decode recovery never promotes Automatic to the highest rung'],
        ['old-quality-flag', 'same retained wrapper starts the second exact 480 descriptor'],
        ['no-quality-flag-reset', 'consuming the first choice clears the flag on the same retained wrapper']
    ];
    for (const [mode, expectedFailure] of cases) {
        const { result, marker } = await runFixture(mode);
        const failure = childDiagnostic(result, mode);
        assertNormalExit(result, mode);
        assert.ok(result.output.includes(`STITCH_UI_FAIL:${expectedFailure}`), `${mode} must fail its actual behavior assertion\n${failure}`);
        const summary = result.output.match(/STITCH_UI_FAIL:\s*(\d+) failures;\s*(\d+) assertions/);
        assert.ok(summary && Number(summary[1]) > 0 && Number(summary[2]) > 0, `${mode} must complete actual failing assertions\n${failure}`);
        assert.throws(() => acceptResult(result, marker));
        t.diagnostic(`${mode}: ${summary[1]} failed of ${summary[2]} actual assertions; rejected despite normal engine exit`);
    }
});

test('removing actual source-transition recovery fails its ready-session behavior', { timeout: 90000 }, async t => {
    const { result, marker } = await runFixture('no-source-transition-recovery');
    assertNormalExit(result, 'no-source-transition-recovery');
    assert.match(result.output, /STITCH_UI_FAIL:ready source transition schedules one bounded automatic reconnect/);
    assert.throws(() => acceptResult(result, marker));
    t.diagnostic('actual transition dispatch removal is rejected despite normal engine exit');
});

test('removing the actual pending-retry guard rejects duplicate transition recovery', { timeout: 90000 }, async t => {
    const { result, marker } = await runFixture('no-source-transition-retry-guard');
    assertNormalExit(result, 'no-source-transition-retry-guard');
    assert.match(result.output, /STITCH_UI_FAIL:source transition preserves one actual error retry without a second timer or budget charge/);
    assert.throws(() => acceptResult(result, marker));
    t.diagnostic('actual pending-retry guard removal creates duplicate timers and is rejected');
});

test('actual live health thresholds and interruption guards reject premature or blanket forgiveness', { timeout: 240000 }, async t => {
    for (const [mode, failure] of [
        ['health-time', '119 healthy seconds cannot forgive transition charges'],
        ['health-media', 'noise interrupts health without forgiving transition debt'],
        ['health-blanket', '120 healthy seconds refund only scheduled transitions and preserve actual error debt'],
        ['health-state', 'non-playing observation clears health before watchdog restarts'],
        ['health-gap', 'gap interrupts health without forgiving transition debt']
    ]) {
        const { result, marker } = await runFixture(mode);
        assertNormalExit(result, mode);
        assert.ok(result.output.includes(`STITCH_UI_FAIL:${failure}`), childDiagnostic(result, mode));
        assert.throws(() => acceptResult(result, marker));
        t.diagnostic(`${mode}: actual health behavior rejects the mutation despite normal engine exit`);
    }
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
