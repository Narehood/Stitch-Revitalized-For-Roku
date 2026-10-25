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
const fixtures = path.join(__dirname, 'fixtures/streamer-pins');

async function write(dir, file, data) {
    const dest = path.join(dir, file);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    await fs.writeFile(dest, data);
}

async function copy(dir, file) {
    await write(dir, file, await fs.readFile(path.join(root, file)));
}

async function tree(dir, folder) {
    for (const entry of await fs.readdir(path.join(root, folder), { withFileTypes: true })) {
        const file = `${folder}/${entry.name}`;
        if (entry.isDirectory()) await tree(dir, file);
        else await copy(dir, file);
    }
}

async function component(dir, folder, name, probe, replacements = []) {
    let xml = await fs.readFile(path.join(root, folder, `${name}.xml`), 'utf8');
    for (const [from, to] of replacements) {
        assert.ok(xml.includes(from), `fixture boundary must match ${from}`);
        xml = xml.replaceAll(from, to);
    }
    const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)]
        .map(match => `<function name="${match[1]}" />`).join('');
    await write(dir, `${folder}/${name}.xml`, xml.replace('</interface>', `${exports}</interface>`)
        .replace('</component>', `<script uri="pkg:/components/${name}-probe.brs" /></component>`));
    await copy(dir, `${folder}/${name}.brs`);
    await write(dir, `components/${name}-probe.brs`, probe);
}

async function build(dir, marker, accountChangeOnly = false) {
    await write(dir, 'manifest', 'title=Local Streamer Pins Regression\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const file of ['source/constants.brs', 'source/utils/config.brs', 'source/utils/recentlyWatched.brs',
        'source/utils/misc.brs', 'source/utils/taskFactory.brs', 'source/utils/contentBuilder.brs',
        'source/utils/lifecycle.brs', 'source/utils/sceneFactory.brs', 'settings/settings.json',
        'components/SceneManager/Group/SceneManagerGroup.xml', 'components/SceneManager/Group/SceneManagerGroup.brs']) await copy(dir, file);
    for (const folder of ['fonts', 'images', 'components/Modules/StatusPanel', 'components/Modules/TwitchContentNode',
        'components/Modules/VideoItem', 'components/Modules/EmojiLabel', 'components/Modules/CirclePoster',
        'components/Modules/MenuBar/ButtonGroupHoriz']) await tree(dir, folder);
    for (const file of ['task.brs', 'TwitchApiTask.xml', 'InfoBoundary.xml']) {
        await write(dir, `components/${file}`, await fs.readFile(path.join(__dirname, 'fixtures/ui', file)));
    }
    await write(dir, 'components/Modules/EmojiLabel/EmojiLabelRegex.brs',
        await fs.readFile(path.join(__dirname, 'fixtures/ui-phase2-player/EmojiLabelRegex.brs')));
    for (const file of ['scene.brs', 'FixtureScene.xml']) await write(dir, `components/${file}`, await fs.readFile(path.join(fixtures, file)));
    await write(dir, 'source/main.brs', (await fs.readFile(path.join(fixtures, 'main.brs'), 'utf8'))
        .replaceAll('__PASS_MARKER__', marker).replace('__ACCOUNT_CHANGE_ONLY__', accountChangeOnly ? 'true' : 'false'));
    await write(dir, 'components/Settings.xml', (await fs.readFile(path.join(__dirname, 'fixtures/ui-startup-player/PageBoundary.xml'), 'utf8')).replaceAll('__NAME__', 'Settings'));
    await component(dir, 'components/Modules/MenuBar', 'MenuBar', '');
    await tree(dir, 'components/Modules/RecentlyWatchedBar');
    await component(dir, 'components/Modules/RecentlyWatchedBar', 'RecentlyWatchedBar', `function fixtureRead() as object
    return { items: m.items, index: m.currentIndex, task: m.liveStatusTask, timer: m.refreshTimer, disposed: m.disposed, accountSection: m.accountSection }
end function
function fixtureOptions() as boolean
    return onKeyEvent("options", true)
end function
sub fixtureRefresh()
    onRefreshTimer()
end sub
sub fixtureStale(task as object)
    onLiveStatusResponse({ getRoSGNode: function() as object
        return m.node
    end function, node: task })
end sub
`);
    await component(dir, 'components/Scenes/ChannelPage', 'ChannelPage', `function fixtureRead() as object
    return { task: m.GetContentTask, rowlist: m.rowlist, disposed: m.disposed }
end function
`, [['<SimpleLabel', '<Label'], ['<InfoPane', '<InfoBoundary'], ['fontSize="32"', ''], ['fontSize="20"', ''],
        ['fontUri="pkg:/fonts/Archivo-Bold.otf"', ''], ['fontUri="pkg:/fonts/Archivo-Regular.otf"', '']]);
    // Only thumbnail I/O is local; native RowList/cards and all handlers execute.
    const page = 'components/Scenes/ChannelPage/ChannelPage.brs';
    await write(dir, page, (await fs.readFile(path.join(root, page), 'utf8')).replaceAll(
        'https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-1280x720.jpg', 'pkg:/images/default_banner.png'));
    const hero = await fs.readFile(path.join(root, 'components/heroScene.brs'), 'utf8');
    const functions = ['buildNode', 'discardScene', 'teardownAllScenes', 'onRecentSelected', 'onRecentItemsChanged', 'onBackPressed', 'onKeyEvent', 'focusedMenuItem',
        'ValidateUserLogin', 'cleanUserData', 'onLogoutFinished'];
    await write(dir, 'components/HeroActual.brs', functions.map(name => {
        const match = hero.match(new RegExp(`^(?:sub|function)\\s+${name}\\b[^\\n]*\\n[\\s\\S]*?^end (?:sub|function)\\s*$`, 'im'));
        assert.ok(match, `production function missing: ${name}`);
        return match[0];
    }).join('\n\n'));
}

function run(zip, cwd) {
    return new Promise((resolve, reject) => {
        // No --registry: native roRegistry is isolated to this engine process.
        const child = spawn(process.execPath, [path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js'),
            path.join(root, 'node_modules/brs-node/bin/brs.cli.js'), zip], { cwd, windowsHide: true });
        let output = '';
        let timedOut = false;
        let exceeded = false;
        const timer = setTimeout(() => { timedOut = true; child.kill(); }, 35000);
        const collect = chunk => {
            if (exceeded) return;
            output += chunk.toString();
            if (Buffer.byteLength(output) > 1024 * 1024) { exceeded = true; child.kill(); }
        };
        child.stdout.on('data', collect);
        child.stderr.on('data', collect);
        child.on('error', error => { clearTimeout(timer); reject(error); });
        child.on('close', code => { clearTimeout(timer); resolve({ code, output, timedOut, exceeded }); });
    });
}

async function checkFixture(t, accountChangeOnly = false) {
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-streamer-pins-'));
    const marker = `STITCH_PINS_PASS:${randomUUID()}`;
    try {
        const dir = path.join(temp, 'package');
        await build(dir, marker, accountChangeOnly);
        const zip = path.join(temp, 'fixture.zip');
        await zipFolder(dir, zip);
        const result = await run(zip, temp);
        const detail = result.output.slice(-20000);
        assert.equal(result.timedOut, false, detail);
        assert.equal(result.exceeded, false, detail);
        assert.equal(result.code, 0, detail);
        assert.doesNotMatch(result.output, /STITCH_PINS_FAIL:|FIXTURE_DRIVER_ERROR:|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|runtime error|BrightScript Debugger/i, detail);
        assert.match(result.output, /EXIT_USER_NAV/, detail);
        const summary = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
        assert.ok(summary && Number(summary[1]) >= (accountChangeOnly ? 25 : 40), detail);
        t.diagnostic(`${summary[1]} actual storage/SceneGraph assertions; native registry is process-local; Task/network/unsupported profile views are boundaries; hardware pixels and video are not tested`);
    } finally {
        const resolved = path.resolve(temp);
        assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
        assert.ok(path.basename(resolved).startsWith('stitch-streamer-pins-'));
        await fs.rm(resolved, { recursive: true, force: true });
    }
}

test('streamer pins execute native registry, merge, limits, Options, focus and first OK/Back', { timeout: 45000 }, checkFixture);

test('streamer pin account changes reject stale Options and refresh after OAuth invalidation', { timeout: 45000 }, async t => {
    await checkFixture(t, true);
});
