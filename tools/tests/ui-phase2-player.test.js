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
const fixtures = path.join(__dirname, 'fixtures/ui-phase2-player');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
// The tracked engine key driver shared with the phase-one player fixture.
const keyDriver = path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js');
const timeoutMs = 60000;
const outputLimit = 1024 * 1024;

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

async function fixture(file) {
    return fs.readFile(path.join(fixtures, file), 'utf8');
}

// Copies a production component unchanged except for read-only inspection
// exports appended to its interface. The probe only reads state or calls the
// component's own handlers; it never replaces production code.
async function addComponent(dir, folder, name, probe = '', xmlName = name) {
    let xml = await fs.readFile(path.join(root, folder, `${xmlName}.xml`), 'utf8');
    if (probe) {
        const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
            .map(match => `<function name="${match[1]}" />`).join('');
        assert.ok(exports, `${name} probe has no fixture exports`);
        xml = xml.replace('</interface>', `${exports}</interface>`)
            .replace('</component>', `<script uri="pkg:/components/${name}Fixture.brs" /></component>`);
        await addFile(dir, `components/${name}Fixture.brs`, probe);
    }
    await addFile(dir, `${folder}/${xmlName}.xml`, xml);
    await copyFile(dir, `${folder}/${xmlName}.brs`);
}

async function addCommon(dir, title, marker, main) {
    await addFile(dir, 'manifest', `title=${title}\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n`);
    for (const file of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/analytics.brs', 'source/utils/uiContrast.brs']) await copyFile(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/CirclePoster']) await copyTree(dir, folder);
    // Explicit I/O boundary: an in-memory registry on the global node.
    await addFile(dir, 'source/utils/config.brs', await fixture('config.brs'));
    await addFile(dir, 'components/PhaseTwoHost.xml', await fixture('PhaseTwoHost.xml'));
    await addFile(dir, 'source/support.brs', (await fixture('support.brs')).replaceAll('__PASS_MARKER__', marker));
    await addFile(dir, 'source/main.brs', await fixture(main));
}

// EmojiLabel runs unchanged; only its pattern source is the engine boundary.
async function addEmojiLabel(dir, probe = '') {
    await addComponent(dir, 'components/Modules/EmojiLabel', 'EmojiLabel', probe);
    await copyFile(dir, 'components/Modules/EmojiLabel/EmojiLabelUtil.brs');
    await addFile(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fixture('EmojiLabelRegex.brs'));
}

const wrapperProbes = {
    StitchVideo: `function fixtureRead() as object
    return { overlay: m.isOverlayVisible, focused: m.currentFocusedButton, caption: m.captionLabel.text, captionVisible: m.caption.visible, controlsX: m.controls.translation[0], scrimWidth: m.scrim.width, tagVisible: m.latencyTag.visible, tagText: m.latencyTag.text, live: m.top.findNode("liveLabel").text, dialogVisible: m.qualityDialog.visible, dialogTitle: m.qualityDialog.title, dialogMessage: m.qualityDialog.message, dialogButtons: m.qualityDialog.buttons }
end function
`,
    CustomVideo: `function fixtureRead() as object
    return { overlay: m.isOverlayVisible, seekMode: m.isSeekMode = true, held: m.buttonHeld, preview: m.currentPositionSeconds, focused: m.currentFocusedButton, hint: m.seekHint.text, hintVisible: m.seekHint.visible, infoVisible: m.infoRow.visible, caption: m.captionLabel.text, captionVisible: m.caption.visible, knob: m.progressDot.color, position: m.timeProgress.text, controlsX: m.controls.translation[0], timeTravelOpen: m.isTimeTravelDialogOpen, lengthText: m.timeTravelLength.text }
end function

sub fixtureObserveHold()
    m.fixtureHoldProgress = []
    m.timeProgress.observeField("text", "fixtureOnHoldProgress")
end sub
sub fixtureOnHoldProgress()
    events = m.fixtureHoldProgress
    events.push({ data: m.timeProgress.text, duration: m.buttonHoldTimer.duration })
    m.fixtureHoldProgress = events
end sub
function fixtureFinishHold() as object
    m.timeProgress.unobserveField("text")
    return m.fixtureHoldProgress
end function
`,
};

async function addWrappers(dir, probes) {
    for (const name of ['StitchVideo', 'CustomVideo']) {
        await addComponent(dir, `components/Modules/${name}`, name, probes ? wrapperProbes[name] : '');
    }
}

async function buildWrappersPackage(dir, marker) {
    await addCommon(dir, 'Phase Two Player Fixture', marker, 'wrappers-main.brs');
    await addEmojiLabel(dir);
    await addWrappers(dir, true);
}

async function buildRetryPackage(dir, marker) {
    await addCommon(dir, 'Phase Two Retry Fixture', marker, 'retry-main.brs');
    await addEmojiLabel(dir);
    await addWrappers(dir, false);
    for (const folder of ['components/SceneManager/Group', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoErrorHandler']) await copyTree(dir, folder);
    await copyFile(dir, 'components/Modules/Chat/Chat.xml');
    await copyFile(dir, 'components/Modules/Chat/Chat.brs');
    // Inert task boundaries with the production interfaces: no worker,
    // network, socket or registry writes.
    for (const file of ['GetTwitchContent.xml', 'GetTwitchContentBoundary.brs', 'TwitchApiTask.xml',
        'RW_AddTask.xml', 'ChatJob.xml', 'EmoteJob.xml']) await addFile(dir, `components/${file}`, await fixture(file));
    await addComponent(dir, 'components/Scenes/VideoPlayer', 'VideoPlayer', `function fixtureRead() as object
    return { task: m.PlayVideo, video: m.video, pending: m.manualRetryPending <> invalid and m.manualRetryPending, dialog: m.errorDialog, recovery: m.recoveryAttempts, reconnect: m.reconnectAttempts, retryTimer: m.retryTimer, reconnectTask: m.reconnectTask }
end function
sub fixtureButtonAgain()
    onErrorDialogButton()
end sub
sub fixtureRetryAgain()
    retryAfterError()
end sub
sub fixtureSpendRecovery(count as integer)
    m.recoveryAttempts = count
    m.reconnectAttempts = count
end sub
`);
    await copyFile(dir, 'components/Scenes/VideoPlayer/RokuPlayback.brs');
}

async function buildChatPackage(dir, marker) {
    await addCommon(dir, 'Phase Two Chat Fixture', marker, 'chat-main.brs');
    await addComponent(dir, 'components/Modules/Chat', 'Chat', `function fixtureNameColor(color as dynamic) as dynamic
    return buildUsername("viewer", color).color
end function
function fixtureLinkColor() as dynamic
    return wordOrImage("https://example.com", true).color
end function
function fixtureCached() as integer
    return m.nameColorCache.count()
end function
function fixtureStatus(state as string) as string
    updateChatStatus(state)
    return m.chatStatus.text
end function
`);
    await addEmojiLabel(dir, `function fixtureRead() as object
    builds = 0
    if m.fixtureBuilds <> invalid then builds = m.fixtureBuilds
    return { builds: builds, compiled: m.emojiRegex <> invalid, failed: m.emojiRegexFailed = true, parts: m.components.getChildCount() }
end function
sub fixtureFailCompile()
    m.fixtureFail = true
end sub
function fixtureCompile() as boolean
    return emojiPattern() <> invalid
end function
function fixtureText() as string
    text = ""
    for i = 0 to m.components.getChildCount() - 1
        child = m.components.getChild(i)
        if child.subtype() = "Label" then text = text + child.text
    end for
    return text
end function
`);
}

function runPackage(zip, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [keyDriver, cli, zip],
            { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
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
        // Wait for the own child to close before its temp directory is removed.
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            resolve({ code, signal, output, timedOut, exceeded });
        });
    });
}

async function runFixture(prefix, build) {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const marker = `STITCH_UI_PASS:${randomUUID()}`;
    try {
        const packageDir = path.join(temp, 'package');
        await build(packageDir, marker);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(packageDir, zip);
        const result = await runPackage(zip, temp);
        const failure = result.output.slice(-16000);
        assert.equal(result.timedOut, false, `fixture timed out\n${failure}`);
        assert.equal(result.exceeded, false, `fixture exceeded output limit\n${failure}`);
        assert.equal(result.code, 0, `fixture exited ${result.code} (${result.signal})\n${failure}`);
        assert.doesNotMatch(result.output, /STITCH_UI_FAIL:|FIXTURE_DRIVER_ERROR|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger|unhandled exception/i, failure);
        assert.match(result.output, /EXIT_USER_NAV/, `fixture did not close normally\n${failure}`);
        const summaries = [...result.output.matchAll(/STITCH_UI_PASS:[0-9a-f-]+:\s*(\d+) assertions/g)];
        assert.equal(summaries.length, 1, `expected exactly one success summary\n${failure}`);
        const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
        assert.ok(summary, `fresh fixture success marker missing\n${failure}`);
        assert.ok(Number(summary[1]) > 0, `fixture executed zero assertions\n${failure}`);
        return Number(summary[1]);
    } finally {
        const resolvedTemp = path.resolve(temp);
        assert.equal(path.dirname(resolvedTemp), path.resolve(os.tmpdir()), 'cleanup must stay directly inside the temp directory');
        assert.ok(path.basename(resolvedTemp).startsWith(prefix), 'cleanup must target this fixture directory');
        await fs.rm(resolvedTemp, { recursive: true, force: true });
    }
}

test('seek preview apply/cancel, initial hold delay, fade, captions and quality marker on both wrappers', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-phase2-player-', buildWrappersPackage);
    t.diagnostic(`${count} assertions; real engine keys and timers; no media is loaded, so playback state is a fixture input`);
});

test('error dialog Try again makes one fresh request and keeps position, quality and chat layout', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-phase2-retry-', buildRetryPackage);
    t.diagnostic(`${count} assertions; content/bookmark/chat tasks are inert boundaries; network and decoding are not tested`);
});

test('chat name contrast cache, EmojiLabel pattern cache and token contrast', { timeout: 90000 }, async t => {
    const count = await runFixture('stitch-ui-phase2-chat-', buildChatPackage);
    t.diagnostic(`${count} assertions; the emoji pattern source is an engine boundary; chat transport never starts`);
});
