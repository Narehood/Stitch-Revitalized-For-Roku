'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {randomUUID, createHash} = require('node:crypto');
const bsc = require('brighterscript');

const root = path.resolve(__dirname, '../..');
const fixture = path.join(__dirname, 'fixtures/roku-demux-polling');
const names = ['rokuDemuxBulk', 'rokuDemuxCore', 'rokuDemuxFetch', 'rokuDemuxCommon', 'rokuDemuxProtocol'];
const cases = ['default-and-trusted-server-wiring', 'changed-unchanged-source-target-floor',
    'successful-dispatch-failure-and-timeout-retry', 'mixed-startup-and-epoch-conversion',
    'map-alias-terminal-and-private-snapshot-release', 'unchanged-publication-deadline-and-clock-quota-bounds'];

function body(source, name) {
    const matches = source.match(new RegExp(`^(?:sub|function) ${name}\\b[^]*?^end (?:sub|function)\\r?$`, 'gmi'));
    assert.equal(matches?.length, 1, `one actual ${name}`);
    return matches[0] + '\n';
}

function child(args, cwd, timeoutMs = 30000) {
    return new Promise(resolve => {
        const processChild = spawn(process.execPath, args, {cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => {timedOut = true; processChild.kill();}, timeoutMs);
        const collect = chunk => {
            bytes += chunk.length;
            if (bytes > 65536) {exceeded = true; processChild.kill(); return;}
            output += chunk.toString();
        };
        processChild.stdout.on('data', collect);
        processChild.stderr.on('data', collect);
        processChild.once('error', error => {startupError = error.name;});
        processChild.once('close', (code, signal) => {
            clearTimeout(timer);
            resolve({code, signal, output, timedOut, exceeded, startupError});
        });
    });
}

function normal(result) {
    const detail = result.output.slice(-12000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    assert.equal(result.signal, null, detail);
    assert.doesNotMatch(result.output, /BRIGHTSCRIPT:\s*ERROR:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger|Syntax Error|unhandled exception/i, detail);
    assert.doesNotMatch(result.output, /PRIVATE_SNAPSHOT|sourceUrl|playlistSnapshot/, 'private source snapshot cannot reach output');
}

function positive(result, marker) {
    normal(result);
    assert.doesNotMatch(result.output, /STITCH_POLL_FAIL:/, result.output);
    const lines = result.output.split(/\r?\n/);
    assert.deepEqual(lines.filter(line => line.startsWith('STITCH_POLL_CASE: ')), cases.map(name => `STITCH_POLL_CASE: ${name}`));
    const summaries = lines.filter(line => line.startsWith('STITCH_POLL_PASS: '));
    assert.equal(summaries.length, 1, result.output);
    assert.ok(summaries[0].startsWith(`STITCH_POLL_PASS: ${marker} `), 'fresh marker required');
    const counts = JSON.parse(summaries[0].slice(`STITCH_POLL_PASS: ${marker} `.length));
    assert.equal(counts.cases, cases.length);
    assert.ok(Number.isSafeInteger(counts.assertions) && counts.assertions > 0);
    assert.ok(counts.pairs >= 9 && counts.starts >= 10, 'actual conversion and Fetch dispatch required');
    return counts;
}

async function withFixture(run) {
    const prefix = 'stitch-roku-polling-';
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const originals = new Map();
    try {
        for (const name of names) {
            const file = `source/utils/${name}.brs`;
            const bytes = await fs.readFile(path.join(root, file));
            originals.set(file, bytes);
        }
        const serverFile = 'components/Tasks/RokuDemuxServer/RokuDemuxServer.brs';
        const server = await fs.readFile(path.join(root, serverFile));
        originals.set(serverFile, server);
        const corpusFile = path.join(__dirname, 'fixtures/roku-demux-epoch-core/corpus.json');
        const corpus = await fs.readFile(corpusFile);
        const provenance = JSON.parse(await fs.readFile(path.join(path.dirname(corpusFile), 'provenance.json')));
        assert.equal(createHash('sha256').update(corpus).digest('hex'), provenance.corpusSha256);
        await fs.writeFile(path.join(dir, 'corpus.json'), corpus);
        await fs.writeFile(path.join(dir, 'manifest'), 'title=Actual Source Poll Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        const main = await fs.readFile(path.join(fixture, 'main.brs'), 'utf8');
        const execute = async (mutation) => {
            for (const name of names) {
                const file = `source/utils/${name}.brs`;
                let source = originals.get(file).toString();
                if (mutation?.file === file) {
                    assert.equal(source.split(mutation.before).length, 2, 'one exact mutation anchor');
                    source = source.replace(mutation.before, mutation.after);
                }
                if (name === 'rokuDemuxFetch') {
                    source = source.replace(/CreateObject\("(roFileSystem|roUrlTransfer)"\)/g, 'pfCreateObject("$1")');
                    for (const [before, after] of [
                        ['Type(event) <> "roUrlEvent"', 'pfEventType(event) <> "roUrlEvent"'],
                        ['payload = ReadAsciiFile(nlInputPath())', 'payload = pfReadInput(nlInputPath())']
                    ]) {
                        assert.equal(source.split(before).length, 2, 'one unavailable native input boundary');
                        source = source.replace(before, after);
                    }
                }
                assert.deepEqual(bsc.Parser.parse(source, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
                await fs.writeFile(path.join(dir, `${name}.brs`), source);
            }
            let wiring = body(server.toString(), 'configureLiveLatency');
            if (mutation?.file === serverFile) {
                assert.equal(wiring.split(mutation.before).length, 2);
                wiring = wiring.replace(mutation.before, mutation.after);
            }
            await fs.writeFile(path.join(dir, 'wiring.brs'), wiring);
            const marker = randomUUID();
            const harness = main.replaceAll('__MARKER__', marker);
            assert.deepEqual(bsc.Parser.parse(harness, {mode: bsc.ParseMode.BrightScript}).diagnostics, []);
            await fs.writeFile(path.join(dir, 'main.brs'), harness);
            const result = await child([path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), '--no-sg', '--root', dir,
                ...names.map(name => `${name}.brs`), 'wiring.brs', 'main.brs'], dir);
            return {...result, marker};
        };
        await run({execute});
        for (const [file, bytes] of originals) assert.deepEqual(await fs.readFile(path.join(root, file)), bytes, 'production bytes unchanged by tests');
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith(prefix));
        await fs.rm(dir, {recursive: true, force: true});
    }
}

test('actual Core/Fetch request-start scheduling preserves source floors, default path, conversion and cleanup', {timeout: 60000}, async t => {
    await withFixture(async ({execute}) => {
        const result = await execute();
        t.diagnostic(JSON.stringify(positive(result, result.marker)));
        t.diagnostic('actual Core/Bulk/Fetch and Server wiring; native URL/filesystem/decoder boundaries mocked, no network/hardware delay claim');
    });
});

test('publication reset, source floor, dispatch and trusted wiring mutations fail at normal exit', {timeout: 150000}, async t => {
    await withFixture(async ({execute}) => {
        for (const mutation of [
            {file: 'source/utils/rokuDemuxCore.brs', before: 'if not state.pollFromRequest then state.nextPoll = nowMs + window.targetDuration * 500&',
                after: 'state.nextPoll = nowMs + window.targetDuration * 500&', failure: 'publication preserves successful request source floor'},
            {file: 'source/utils/rokuDemuxCore.brs', before: 'interval = target * 1000&', after: 'interval = target * 500&', failure: 'first changed source waits full target from dispatch'},
            {file: 'source/utils/rokuDemuxCore.brs', before: 'if state.playlistSnapshot = text then interval = target * 500&', after: "' Removed unchanged snapshot half target", failure: 'identical source uses half target without fabricated publication'},
            {file: 'source/utils/rokuDemuxCore.brs', before: 'state.nextPoll = state.playlistRequestStartedAt + interval', after: 'state.nextPoll = nowMs + interval', failure: 'first changed source waits full target from dispatch'},
            {file: 'source/utils/rokuDemuxFetch.brs', before: 'if intent.kind = "playlist" then nativeLivePlaylistStarted(state, nowMs)', after: "' Removed successful GET callback", failure: 'successful actual GET records request dispatch'},
            {file: 'components/Tasks/RokuDemuxServer/RokuDemuxServer.brs', before: 'state.pollFromRequest = m.top.lowLatency', after: 'state.pollFromRequest = true', failure: 'trusted default retains14s and original polling'}
        ]) {
            const result = await execute(mutation);
            normal(result);
            assert.ok(result.output.includes(`STITCH_POLL_FAIL: polling-fixture: ${mutation.failure}`), result.output);
            assert.throws(() => positive(result, result.marker));
            t.diagnostic(`rejected: ${mutation.failure}`);
        }
    });
});
