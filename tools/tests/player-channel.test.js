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
const fixtures = path.join(__dirname, 'fixtures/player-channel');
const shared = path.join(__dirname, 'fixtures/roku-demux-player');
const startup = path.join(__dirname, 'fixtures/ui-startup-player');
const owner = path.join(__dirname, 'fixtures/roku-demux-root-back');
const prefix = 'stitch-player-channel-';
const tracked = ['components/heroScene.brs', 'components/Scenes/VideoPlayer/VideoPlayer.brs',
    'components/Scenes/Following/Following.brs',
    'components/Scenes/VideoPlayer/ChannelFollow.brs',
    'components/Scenes/VideoPlayer/RokuPlayback.brs', 'components/Modules/StitchVideo/StitchVideo.brs',
    'components/Modules/CustomVideo/CustomVideo.brs', 'components/Scenes/ChannelPage/ChannelPage.brs',
    'components/Modules/RokuDemuxSession/RokuDemuxSession.brs'];

async function snapshots() {
    return Promise.all(tracked.map(async file => [file, createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex')]));
}

async function build(dir, marker) {
    async function add(file, data) {
        const dest = path.join(dir, file);
        await fs.mkdir(path.dirname(dest), { recursive: true });
        await fs.writeFile(dest, data);
    }
    async function copy(file) { await add(file, await fs.readFile(path.join(root, file))); }
    async function tree(folder) {
        for (const entry of await fs.readdir(path.join(root, folder), { withFileTypes: true })) {
            const file = `${folder}/${entry.name}`;
            if (entry.isDirectory()) await tree(file);
            else await copy(file);
        }
    }
    async function probe(folder, name, file, from = fixtures) {
        const original = await fs.readFile(path.join(root, folder, `${name}.xml`), 'utf8');
        const source = await fs.readFile(path.join(from, `${file}.brs`), 'utf8');
        const exports = [...source.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)].map(match => `<function name="${match[1]}" />`).join('');
        await add(`${folder}/${name}.xml`, original.replace('</interface>', `${exports}</interface>`)
            .replace('</component>', `<script uri="pkg:/components/${name}Probe.brs" /></component>`));
        await add(`components/${name}Probe.brs`, source);
    }
    for (const folder of ['source/utils', 'fonts', 'images', 'components/SceneManager/Scene', 'components/SceneManager/Group',
        'components/Modules/CirclePoster', 'components/Modules/MenuBar', 'components/Modules/StatusPanel',
        'components/Modules/RecentlyWatchedBar', 'components/Modules/TwitchContentNode', 'components/Modules/VideoErrorHandler',
        'components/Modules/StitchVideo', 'components/Modules/CustomVideo', 'components/Modules/AdCountdown', 'components/Modules/EmojiLabel',
        'components/Modules/VideoItem', 'components/Scenes/Following', 'components/Scenes/ChannelPage', 'components/Scenes/VideoPlayer',
        'components/Modules/RokuDemuxSession']) await tree(folder);
    for (const file of ['source/constants.brs', 'source/changelog.brs', 'components/heroScene.xml', 'components/heroScene.brs']) await copy(file);
    for (const asset of ['ChatAnimationAsset.xml', 'ChatAnimationAsset.brs', 'ChatGifAtlas.brs']) await copy(`components/Modules/Chat/ChatAnimationAsset/${asset}`);
    for (const file of ['Chat.xml', 'Chat.brs', 'ChatAnimations.brs']) await copy(`components/Modules/Chat/${file}`);
    await probe('components', 'heroScene', 'HeroProbe');
    await probe('components/Scenes/VideoPlayer', 'VideoPlayer', 'PlayerProbe');
    for (const name of ['StitchVideo', 'CustomVideo']) await probe(`components/Modules/${name}`, name, 'WrapperProbe');
    await probe('components/Modules/Chat', 'Chat', 'ChatProbe');
    await probe('components/Scenes/ChannelPage', 'ChannelPage', 'ChannelProbe');
    await probe('components/Scenes/Following', 'Following', 'FollowingProbe');
    await probe('components/Modules/RokuDemuxSession', 'RokuDemuxSession', 'ManagerProbe', owner);
    // Actual ownership manager; only the native socket/media worker is inert.
    const managerFile = 'components/Modules/RokuDemuxSession/RokuDemuxSession.brs';
    const manager = await fs.readFile(path.join(root, managerFile), 'utf8');
    assert.equal(manager.split('CreateObject("roSGNode", "RokuDemuxServer")').length, 2);
    await add(managerFile, manager.replace('CreateObject("roSGNode", "RokuDemuxServer")', 'CreateObject("roSGNode", "ChannelWorkerBoundary")')
        .replace('workerType = "RokuVodDemuxServer"', 'workerType = "ChannelWorkerBoundary"'));
    await add('components/ChannelWorkerBoundary.xml', `<component name="ChannelWorkerBoundary" extends="Group"><interface>
      <field id="sessionId" type="string" /><field id="inputDescriptor" type="assocarray" />
      <field id="experimentalMode" type="boolean" /><field id="cacheBudgetBytes" type="integer" />
      <field id="listenPort" type="integer" /><field id="functionName" type="string" />
      <field id="control" type="string" onChange="onControl" /><field id="state" type="string" alwaysNotify="true" />
      <field id="ready" type="assocarray" alwaysNotify="true" /><field id="result" type="assocarray" alwaysNotify="true" />
      <field id="enableAdMetadata" type="boolean" /><field id="enableSourceTransitions" type="boolean" /><field id="lowLatency" type="boolean" />
      <field id="stopRequested" type="boolean" /></interface><script uri="ChannelWorkerBoundary.brs" /></component>`);
    await add('components/ChannelWorkerBoundary.brs', 'sub onControl()\n    if m.top.control = "run" then m.top.state = "run"\n    if m.top.control = "stop" then m.top.state = "stop"\nend sub\n');
    await add('source/utils/config.brs', `${await fs.readFile(path.join(startup, 'config.brs'), 'utf8')}\n${await fs.readFile(path.join(__dirname, 'fixtures/ui-account-settings/registry.brs'), 'utf8')}`);
    for (const file of ['TwitchApiTask.xml', 'RW_AddTask.xml', 'GetTwitchContent.xml', 'GetTwitchContentBoundary.brs',
        'ChatJob.xml', 'EmoteJob.xml']) await add(`components/${file}`, await fs.readFile(path.join(shared, file)));
    await add('components/TwitchEngagementTask.xml', await fs.readFile(path.join(__dirname, 'fixtures/ui-phase2-player/TwitchEngagementTask.xml')));
    await add('components/LowLatencyRelay.xml', `<component name="LowLatencyRelay" extends="Group"><interface>
      <field id="sourceUrl" type="string" /><field id="stopRequested" type="boolean" /><field id="control" type="string" />
      <field id="status" type="assocarray" /><field id="ended" type="boolean" /></interface></component>`);
    await add('components/Modules/EmojiLabel/EmojiLabelRegex.brs', await fs.readFile(path.join(shared, 'EmojiLabelRegex.brs')));
    await add('components/InfoBoundary.xml', await fs.readFile(path.join(__dirname, 'fixtures/ui/InfoBoundary.xml')));
    const page = await fs.readFile(path.join(startup, 'PageBoundary.xml'), 'utf8');
    for (const name of ['Settings', 'LoginPage', 'Browse', 'Search', 'GamePage']) await add(`components/${name}.xml`, page.replaceAll('__NAME__', name));
    // Engine widget boundaries; all production ChannelPage query/navigation runs.
    const channelXml = 'components/Scenes/ChannelPage/ChannelPage.xml';
    const xml = await fs.readFile(path.join(dir, channelXml), 'utf8');
    await add(channelXml, xml.replace('<InfoPane', '<InfoBoundary').replaceAll('<SimpleLabel', '<Label')
        .replaceAll(/fontSize="\d+"/g, '').replaceAll(/fontUri="[^"]+"/g, ''));
    await add('components/CardBoundary.xml', await fs.readFile(path.join(startup, 'CardBoundary.xml')));
    const followingXml = 'components/Scenes/Following/Following.xml';
    await add(followingXml, (await fs.readFile(path.join(dir, followingXml), 'utf8')).replace('itemComponentName="VideoItem"', 'itemComponentName="CardBoundary"'));
    const statusXml = 'components/Modules/StatusPanel/StatusPanel.xml';
    await add(statusXml, (await fs.readFile(path.join(root, statusXml), 'utf8'))
        .replace('<Font role="textFont" uri="pkg:/fonts/Archivo-Bold.otf" size="20" />', '')
        .replace('<Font role="focusedTextFont" uri="pkg:/fonts/Archivo-Bold.otf" size="20" />', ''));
    await add('manifest', 'title=Offline Player Channel Navigation\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    await add('source/main.brs', (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8')).replaceAll('__PASS_MARKER__', marker));
    return add;
}

function run(zip, cwd) {
    return new Promise(resolve => {
        const child = spawn(process.execPath, [path.join(startup, 'key-driver.js'), path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip],
            { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '', bytes = 0, timedOut = false, exceeded = false, startupError;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 90000);
        const collect = data => {
            if (exceeded) return;
            bytes += data.length;
            if (bytes > 1024 * 1024) { exceeded = true; child.kill(); return; }
            output += data.toString();
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.once('error', error => { startupError = error; });
        child.once('close', code => { clearTimeout(timer); resolve({ code, output, timedOut, exceeded, startupError }); });
    });
}

function positive(result, marker) {
    const detail = result.output.slice(-24000);
    assert.equal(result.startupError, undefined, detail);
    assert.equal(result.timedOut, false, detail);
    assert.equal(result.exceeded, false, detail);
    assert.equal(result.code, 0, detail);
    // brs-node cannot store these inherited ContentNode array fields. Its
    // callback attribution can point to the unchanged ContentNode observer.
    const unexpected = result.output.split(/\r?\n/).filter(line => /BRIGHTSCRIPT:\s*ERROR:/i.test(line)
        && !/^BRIGHTSCRIPT: ERROR: roSGNode.AddReplace: "TwitchContentNode\.(?:Streams|streams|StreamQualities|streamqualities)": Type mismatch! pkg:\/(?:\.\/pkg:\/)?components\/(?:Scenes\/VideoPlayer\/(?:RokuPlayback|VideoPlayer)|Modules\/TwitchContentNode\/TwitchContentNode)\.brs\(\d+\)$/.test(line));
    assert.deepEqual(unexpected, [], detail);
    assert.doesNotMatch(result.output, /CHANNEL_ASSERT_FAIL:|CHANNEL_FAIL_SUMMARY:|EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger>|unhandled exception|Syntax Error|failed to set up component/i, detail);
    assert.match(result.output, /EXIT_USER_NAV/, detail);
    const summaries = [...result.output.matchAll(new RegExp(`${marker}:\\s*(\\d+) assertions`, 'g'))];
    assert.equal(summaries.length, 1, detail);
    assert.ok(Number(summaries[0][1]) >= 100, detail);
    return Number(summaries[0][1]);
}

test('remote channel actions pin without interrupting playback and replace Hero Player only after cleanup', { timeout: 240000 }, async t => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
    const before = await snapshots();
    try {
        const marker = `STITCH_PLAYER_CHANNEL_PASS:${randomUUID()}`;
        const packageDir = path.join(dir, 'package');
        const add = await build(packageDir, marker);
        const zip = path.join(dir, 'positive.zip');
        await zipFolder(packageDir, zip);
        const result = await run(zip, dir);
        t.diagnostic(`${positive(result, marker)} actual Hero/Player/wrapper/ChannelPage/chat/manager assertions; remote wrapper keys and native dialog button event boundary`);
        assert.throws(() => positive(result, 'STALE_MARKER'));
        for (const control of [{ timedOut: true }, { exceeded: true }, { code: 1 }]) assert.throws(() => positive({ ...result, ...control }, marker));
        // Removing the actual exit barrier must fail the composed local scenarios.
        const file = 'components/Scenes/VideoPlayer/VideoPlayer.brs';
        const source = await fs.readFile(path.join(root, file), 'utf8');
        assert.equal(source.split('if not stopRokuPlayback(true)').length, 2);
        await add(file, source.replace('if not stopRokuPlayback(true)', 'if true'));
        const negativeZip = path.join(dir, 'no-cleanup-barrier.zip');
        await zipFolder(packageDir, negativeZip);
        const negative = await run(negativeZip, dir);
        assert.equal(negative.timedOut, false, negative.output.slice(-16000));
        assert.equal(negative.code, 0, negative.output.slice(-16000));
        assert.doesNotMatch(negative.output, /EXIT_BRIGHTSCRIPT_CRASH|runtime error|BrightScript Debugger>|Syntax Error/, negative.output.slice(-16000));
        assert.match(negative.output, /CHANNEL_ASSERT_FAIL: local channel action waits for the owned worker and Video/, negative.output.slice(-16000));
        assert.throws(() => positive(negative, marker));
        assert.deepEqual(await snapshots(), before, 'production sources stay frozen across engine fixtures');
    } finally {
        const resolved = path.resolve(dir);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith(prefix));
        await fs.rm(resolved, { recursive: true, force: true });
    }
});
