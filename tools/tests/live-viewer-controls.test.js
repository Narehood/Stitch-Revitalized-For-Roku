'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');

const root = path.resolve(__dirname, '../..');
const shared = path.join(__dirname, 'fixtures/ui-phase2-player');
const fixtures = path.join(__dirname, 'fixtures/live-viewer-controls');
const prefix = 'stitch-live-viewer-controls-';

async function addFile(dir, file, data) {
    const dest = path.join(dir, file);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    await fs.writeFile(dest, data);
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

async function buildPackage(dir, marker) {
    await addFile(dir, 'manifest', 'title=Offline Live Viewer Controls\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/analytics.brs', 'source/utils/recentlyWatched.brs', 'source/utils/uiContrast.brs', 'source/utils/ircEmotes.brs', 'source/utils/ircGifs.brs', 'source/utils/chatAnimationGif.brs',
        'source/utils/twitchAdCountdown.brs', 'source/utils/twitchAdClock.brs',
        'source/utils/rokuDemuxDescriptor.brs', 'source/utils/rokuVodIndex.brs',
        'source/utils/rokuVodDescriptor.brs', 'source/utils/rokuVodRuntime.brs',
        'source/utils/playbackHls.brs', 'source/utils/deviceCapabilities.brs',
        'source/utils/chatAnimationWebp.brs']) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'locale', 'components/SceneManager/Group',
        'components/Modules/CirclePoster', 'components/Modules/AdCountdown',
        'components/Modules/EmojiLabel', 'components/Modules/StitchVideo',
        'components/Modules/CustomVideo', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoErrorHandler', 'components/Modules/Chat/ChatAnimationAsset',
        'components/Scenes/VideoPlayer']) await copyTree(dir, folder);
    for (const file of ['Chat.xml', 'Chat.brs', 'ChatAnimations.brs']) await copyFile(dir, `components/Modules/Chat/${file}`);
    // Existing offline boundaries supply registry and transport contracts;
    // production playback, wrapper and label handlers are copied unchanged.
    await addFile(dir, 'source/utils/config.brs', await fs.readFile(path.join(shared, 'config.brs')));
    for (const file of ['GetTwitchContent.xml', 'GetTwitchContentBoundary.brs', 'TwitchApiTask.xml',
        'RW_AddTask.xml', 'ChatJob.xml', 'EmoteJob.xml', 'TwitchEngagementTask.xml']) {
        await addFile(dir, `components/${file}`, await fs.readFile(path.join(shared, file)));
    }
    // brs-engine uses JS regex and cannot compile the native PCRE emoji pattern.
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fs.readFile(path.join(shared, 'EmojiLabelRegex.brs')));
    await addFile(dir, 'components/PhaseTwoHost.xml', await fs.readFile(path.join(shared, 'PhaseTwoHost.xml')));
    await addFile(dir, 'source/support.brs', (await fs.readFile(path.join(shared, 'support.brs'), 'utf8')).replaceAll('__PASS_MARKER__', marker));
    await addFile(dir, 'source/main.brs', await fs.readFile(path.join(fixtures, 'main.brs')));
    // Read-only access to the actual response task and resulting wrapper.
    const xmlPath = 'components/Scenes/VideoPlayer/VideoPlayer.xml';
    const xml = await fs.readFile(path.join(root, xmlPath), 'utf8');
    await addFile(dir, xmlPath, xml.replace('</interface>', '<function name="fixtureRead" /></interface>')
        .replace('</component>', '<script uri="pkg:/components/ViewerProbe.brs" /></component>'));
    await addFile(dir, 'components/ViewerProbe.brs', 'function fixtureRead() as object\n    return { task: m.PlayVideo, video: m.video }\nend function\n');
}

function runPackage(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js'),
            path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip],
        { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '';
        let bytes = 0;
        let exceeded = false;
        let timedOut = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 45000);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > 1024 * 1024) { exceeded = true; child.kill(); return; }
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

test('live viewers propagate through VideoPlayer and fit the actual controls in both chat layouts', { timeout: 60000 }, async t => {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    try {
        const dir = path.join(temp, 'package');
        await buildPackage(dir, marker);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(dir, zip);
        const result = await runPackage(zip, temp);
        const failure = result.output.slice(-20000);
        assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
        assert.equal(result.exceeded, false, `fixture exceeded output limit\n${failure}`);
        assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
        assert.doesNotMatch(result.output, /STITCH_UI_FAIL:|FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|unhandled exception/i, failure);
        assert.match(result.output, /EXIT_USER_NAV/, `fixture did not close normally\n${failure}`);
        const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
        assert.ok(summary, `fresh fixture success marker missing\n${failure}`);
        assert.ok(Number(summary[1]) >= 100, `expected the full viewer regression coverage\n${failure}`);
        t.diagnostic(`${summary[1]} assertions; actual VideoPlayer/wrappers/labels, inert tasks and registry; native font pixels and decoding require native QA`);
    } finally {
        const target = path.resolve(temp);
        assert.equal(path.dirname(target), path.resolve(os.tmpdir()), 'cleanup must stay directly inside the temp directory');
        assert.ok(path.basename(target).startsWith(prefix), 'cleanup must target this fixture directory');
        await fs.rm(target, { recursive: true, force: true });
    }
});
