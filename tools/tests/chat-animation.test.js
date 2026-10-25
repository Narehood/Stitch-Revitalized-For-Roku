'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { zipFolder } = require('roku-deploy');
const corpus = require('./fixtures/chat-animation/corpus');
const root = path.resolve(__dirname, '../..');
const fixtures = path.join(__dirname, 'fixtures/chat-animation');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');

async function add(dir, name, data) {
    const file = path.join(dir, name);
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, data);
}
async function copy(dir, name) { await add(dir, name, await fs.readFile(path.join(root, name))); }
async function fixture(name) { return fs.readFile(path.join(fixtures, name), 'utf8'); }
async function run(args, cwd, timeout = 45000) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, args, {cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe']});
        let output = '', timedOut = false, excessive = false;
        const timer = setTimeout(() => {timedOut = true; child.kill();}, timeout);
        const collect = data => {
            output += data.toString();
            if (output.length > 1024 * 1024) {excessive = true; child.kill();}
        };
        child.stdout.on('data', collect); child.stderr.on('data', collect);
        child.once('error', reject);
        child.once('close', code => {clearTimeout(timer); resolve({code, output, timedOut, excessive});});
    });
}
function accept(result, marker) {
    assert.equal(result.timedOut, false, result.output.slice(-12000));
    assert.equal(result.excessive, false);
    assert.equal(result.code, 0, result.output.slice(-12000));
    assert.doesNotMatch(result.output, /CHAT_ANIMATION_FAIL:|STITCH_UI_FAIL:|runtime error|BrightScript Debugger|EXIT_BRIGHTSCRIPT_CRASH|failed to set up component|unhandled exception/i);
    const count = result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
    assert.ok(count && Number(count[1]) > 0, `missing fresh nonzero test summary\n${result.output.slice(-12000)}`);
    return Number(count[1]);
}
async function execute(build, sg = false) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-chat-animation-'));
    const marker = `CHAT_ANIMATION_PASS_${randomUUID()}`;
    try {
        await build(dir, marker);
        if (sg) {
            const zip = path.join(dir, 'app.zip');
            await zipFolder(path.join(dir, 'package'), zip);
            const driver = path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js');
            const result = await run([driver, cli, zip], dir, 60000);
            assert.match(result.output, /EXIT_USER_NAV/);
            return accept(result, marker);
        }
        const files = (await fs.readdir(dir)).filter(name => name.endsWith('.brs'));
        return accept(await run([cli, '--no-sg', '--root', dir, ...files], dir), marker);
    } finally {
        assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith('stitch-chat-animation-'));
        await fs.rm(dir, {recursive: true, force: true});
    }
}

test('actual WebP admission parses real PETPET and generated bounded/malformed binary containers', async t => {
    const count = await execute(async (dir, marker) => {
        await add(dir, 'parser.brs', await fs.readFile(path.join(root, 'source/utils/chatAnimationWebp.brs')));
        await add(dir, 'main.brs', (await fixture('admission-main.brs')).replace('__PASS_MARKER__', marker));
        await add(dir, 'cases.json', JSON.stringify(corpus.cases.map(({bytes, ...sample}) => sample)));
        for (const sample of corpus.cases) await add(dir, `${sample.name}.webp`, sample.bytes);
    });
    t.diagnostic(`${count} actual BrightScript parser assertions; no image decoding is simulated by admission`);
});

test('animation setting translations preserve Spanish and Portuguese UTF-8 characters', async () => {
    const decoder = new TextDecoder('utf-8', {fatal: true});
    for (const [locale, title, words] of [
        ['en_US', 'Animate chat emotes', ['Other emotes stay still']],
        ['es_MX', 'Animar emotes del chat', ['Los dem\u00e1s emotes permanecen est\u00e1ticos']],
        ['pt_BR', 'Animar emotes do chat', ['emote vis\u00edvel', 'Roku compat\u00edveis']],
    ]) {
        const xml = decoder.decode(await fs.readFile(path.join(root, `locale/${locale}/translations.ts`)));
        const message = xml.match(/<source>Animate one visible emote[^<]+<\/source><translation>([^<]+)<\/translation>/);
        assert.ok(message, `${locale} animation description`);
        for (const word of words) assert.ok(message[1].includes(word), `${locale}: ${word}`);
        assert.ok(xml.includes(`<translation>${title}</translation>`));
    }
});

test('animation filesystem scripts belong exclusively to Task XML and are not exported to render callbacks', async () => {
    const chatDir = path.join(root, 'components/Modules/Chat');
    const entries = await fs.readdir(chatDir, {recursive: true});
    const scripts = new Map();
    for (const name of entries.filter(name => name.endsWith('.xml'))) {
        const file = path.join(chatDir, name);
        const xml = await fs.readFile(file, 'utf8');
        for (const [, uri] of xml.matchAll(/<script\b[^>]*\buri="([^"]+)"/g)) {
            const script = uri.startsWith('pkg:/') ? path.join(root, uri.slice(5)) : path.resolve(path.dirname(file), uri);
            const owners = scripts.get(script) || [];
            owners.push({name, xml});
            scripts.set(script, owners);
        }
    }
    let count = 0;
    for (const [file, owners] of scripts) {
        const source = await fs.readFile(file, 'utf8');
        if (!/createObject\("roFileSystem"\)/i.test(source)) continue;
        count++;
        for (const {name, xml} of owners) {
            assert.match(xml, /<component\b[^>]*extends="Task"/, `${name}: filesystem script must be Task-owned`);
            assert.doesNotMatch(xml, /<function\b|\bonChange\s*=/i, `${name}: filesystem helpers cannot be exposed as render callbacks`);
        }
        const init = source.match(/^sub init\(\)[^]*?^end sub/m)?.[0];
        assert.match(init, /functionName = "fetchAnimation"/);
        assert.doesNotMatch(init, /roFileSystem|fetchAnimation\(/);
    }
    assert.equal(count, 1, 'one filesystem-owning animation Task');
    const renderer = await fs.readFile(path.join(chatDir, 'ChatAnimations.brs'), 'utf8');
    assert.doesNotMatch(renderer, /roFileSystem|\.(?:readFile|writeFile|createDirectory|stat|exists)\s*\(/i);
});

test('actual BTTV and 7TV producers publish static strings and separate URI-keyed animation descriptors', async t => {
    const count = await execute(async (dir, marker) => {
        const source = await fs.readFile(path.join(root, 'components/Modules/Chat/EmoteJob/EmoteJob.brs'), 'utf8');
        await add(dir, 'producer.brs', source.replace(/^sub main\(\)/m, 'sub runEmoteJob()'));
        await add(dir, 'helpers.brs', await fs.readFile(path.join(root, 'source/utils/ircEmotes.brs')));
        await add(dir, 'main.brs', (await fixture('providers-main.brs')).replace('__PASS_MARKER__', marker));
    });
    t.diagnostic(`${count} producer/selector assertions; provider HTTP and registry are explicit offline boundaries`);
});

async function buildAsset(dir, marker, mutate = source => source) {
    const source = mutate(await fs.readFile(path.join(root, 'components/Modules/Chat/ChatAnimationAsset/ChatAnimationAsset.brs'), 'utf8'));
    assert.equal((source.match(/type\(event\) = "roUrlEvent"/g) || []).length, 1);
    const task = source.replace(/\bcreateObject\("(roFileSystem|roMessagePort|roTimespan|roUrlTransfer|roByteArray)"\)/gi, 'fixtureCreateObject("$1")')
        .replace(/\bwait\(/gi, 'fixtureWait(').replace('type(event) = "roUrlEvent"', 'fixtureIsUrlEvent(event)');
    await add(dir, 'task.brs', task);
    await add(dir, 'parser.brs', await fs.readFile(path.join(root, 'source/utils/chatAnimationWebp.brs')));
    await add(dir, 'main.brs', (await fixture('asset-main.brs')).replace('__PASS_MARKER__', marker));
    await add(dir, 'petpet.webp', corpus.petpet);
    await add(dir, 'oversize.webp', Buffer.alloc(2097152));
    await add(dir, 'one-mib.webp', corpus.cases.find(sample => sample.name === 'one-mib').bytes);
    await add(dir, 'catjam.webp', corpus.catjam);
    await add(dir, 'sourpls.webp', corpus.sourpls);
}

test('actual transfer logic requires bounded HEAD before GET, shares one deadline and strictly admits final files', async t => {
    const count = await execute(buildAsset);
    t.diagnostic(`${count} transfer assertions; actual filesystem allocation/stat/deletion, controlled HTTP/clock inputs`);
});

test('preflight regression rejects GET/file creation when HEAD is oversized or unknown', async () => {
    await assert.rejects(execute((dir, marker) => buildAsset(dir, marker, source => {
        const admission = 'expectedBytes = chatAnimationContentLength(event)';
        assert.equal(source.split(admission).length, 2);
        return source.replace(admission, `${admission}\n            if expectedBytes = 0 then expectedBytes = 1048576`);
    })), /invalid\/oversized HEAD produces ZERO GETs\/files: head-oversize/);
});

async function buildChat(dir, marker, nativeMutation = '', scenario = 'testChatAnimations') {
    dir = path.join(dir, 'package');
    await add(dir, 'manifest', 'title=Chat Animation Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
    for (const name of ['source/constants.brs', 'source/utils/misc.brs', 'source/utils/taskFactory.brs',
        'source/utils/uiContrast.brs', 'source/utils/ircEmotes.brs', 'source/utils/ircParser.brs', 'source/utils/chatAnimationWebp.brs',
        'components/Modules/EmojiLabel/EmojiLabelRegex.brs', 'components/Modules/EmojiLabel/EmojiLabelUtil.brs']) await copy(dir, name);
    const previous = 'tools/tests/fixtures/ui-phase2-player/';
    for (const name of ['ChatJob.xml', 'EmoteJob.xml', 'PhaseTwoHost.xml']) await add(dir, `components/${name}`, await fs.readFile(path.join(root, previous, name)));
    await add(dir, 'source/utils/config.brs', await fs.readFile(path.join(root, previous, 'config.brs')));
    await add(dir, 'source/support.brs', (await fs.readFile(path.join(root, previous, 'support.brs'), 'utf8')).replace('__PASS_MARKER__', marker));
    const probe = await fixture('ChatProbe.brs');
    const exports = [...probe.matchAll(/^(?:sub|function) (fixture\w+)\(/gm)].map(m => `<function name="${m[1]}" />`).join('');
    const xml = (await fs.readFile(path.join(root, 'components/Modules/Chat/Chat.xml'), 'utf8'))
        .replace('</interface>', `${exports}</interface>`).replace('</component>', '<script uri="pkg:/components/ChatProbe.brs" /><script uri="pkg:/source/utils/chatAnimationWebp.brs" /></component>');
    await add(dir, 'components/Modules/Chat/Chat.xml', xml);
    await copy(dir, 'components/Modules/Chat/Chat.brs');
    const source = await fs.readFile(path.join(root, 'components/Modules/Chat/ChatAnimations.brs'), 'utf8');
    assert.equal(source.split('createObject("roSGNode", nodeType)').length, 2);
    let adapted = source.replace('createObject("roSGNode", nodeType)', 'fixtureNativeNode(nodeType)')
        .replace('createObject("roSGNode", "ChatAnimationAsset")', 'fixtureAssetTask()')
        .replaceAll('m.global.setField("chatAnimationStorageOwners", owners)', 'fixturePublishStorageOwners(owners)')
        .replace('sub onChatAnimationStorageOwners(event as object)', 'sub onChatAnimationStorageOwners(event as object)\n    fixtureRecordStorageCallback()');
    if (nativeMutation) adapted = nativeMutation(adapted);
    await add(dir, 'components/Modules/Chat/ChatAnimations.brs', adapted);
    await add(dir, 'components/ChatProbe.brs', probe);
    await add(dir, 'components/AnimatedImageBoundary.xml', await fixture('AnimatedImageBoundary.xml'));
    const assetDir = 'components/Modules/Chat/ChatAnimationAsset/';
    const assetXml = (await fs.readFile(path.join(root, assetDir, 'ChatAnimationAsset.xml'), 'utf8'))
        .replace('</interface>', `<field id="fixtureSource" type="string" value="petpet.webp" />
            <field id="fixtureRelease" type="bool" /><field id="fixtureStarted" type="bool" /><field id="fixtureHeadPending" type="bool" />
            <field id="fixtureCancelled" type="bool" /><field id="fixtureWriteOnCancel" type="bool" />
            <field id="fixtureLateWrite" type="bool" /><field id="fixtureHoldAfterResponse" type="bool" />
            <field id="fixtureDropResponse" type="bool" />
            <field id="fixtureLockedPath" type="string" /><field id="fixtureMode" type="string" />
            <field id="fixtureDeleteCount" type="integer" /></interface>`)
        .replace('</component>', '<script uri="AssetBoundary.brs" /></component>');
    await add(dir, assetDir + 'ChatAnimationAsset.xml', assetXml);
    const asset = await fs.readFile(path.join(root, assetDir, 'ChatAnimationAsset.brs'), 'utf8');
    await add(dir, assetDir + 'ChatAnimationAsset.brs', asset
        .replace('createObject("roUrlTransfer")', 'fixtureTransfer()')
        .replace('event = wait(50, port)', 'event = fixtureWait(50, port)')
        .replace('type(event) = "roUrlEvent"', 'event <> invalid')
        .replaceAll('fs.delete(path)', 'fixtureDelete(fs, path)')
        .replaceAll('fs.delete(directory)', 'fixtureDelete(fs, directory)')
        .replace('m.top.response = result', 'if not m.top.fixtureDropResponse then m.top.response = result\n    fixtureAfterResponse()'));
    await add(dir, assetDir + 'AssetBoundary.brs', await fixture('AssetBoundary.brs'));
    const providerDir = 'components/Modules/Chat/EmoteJob/';
    await copy(dir, providerDir + 'EmoteJob.brs');
    const providerXml = (await fs.readFile(path.join(root, providerDir, 'EmoteJob.xml'), 'utf8'))
        .replace('name="EmoteJob"', 'name="ProviderProbe"')
        .replace('pkg:/source/utils/http.brs', 'ProviderBoundary.brs');
    await add(dir, providerDir + 'ProviderProbe.xml', providerXml);
    await add(dir, providerDir + 'ProviderBoundary.brs', await fixture('ProviderBoundary.brs'));
    await add(dir, 'source/main.brs', (await fixture('chat-main.brs')).replace('__CHAT_SCENARIO__', scenario));
    await add(dir, 'petpet.webp', corpus.petpet);
    await add(dir, 'one-mib.webp', corpus.cases.find(sample => sample.name === 'one-mib').bytes);
    for (const font of ['Archivo-Regular.otf', 'Archivo-Bold.otf']) await copy(dir, `fonts/${font}`);
}

test('actual Chat renderer keeps one visible native owner, restores static images and disposes tasks/files on every removal path', {timeout: 90000}, async t => {
    const count = await execute((dir, marker) => buildChat(dir, marker), true);
    t.diagnostic(`${count} actual renderer/Task/filesystem assertions; only native AnimatedImage and HTTP are boundaries, not proof of native animation`);
});

test('actual Chat instances reserve one global worker and cache through disposal, failed cleanup and completed handoff', {timeout: 90000}, async t => {
    const count = await execute((dir, marker) => buildChat(dir, marker, '', 'testSharedOwnership'), true);
    t.diagnostic(`${count} cross-instance renderer/Task/real-file assertions, including retained 4 MiB cache and held deletion completion`);
});

test('actual release observers wake only visible waiters and survive synchronous acquisition callbacks', {timeout: 90000}, async t => {
    const count = await execute((dir, marker) => buildChat(dir, marker, '', 'testStorageWaiterLifecycle'), true);
    t.diagnostic(`${count} actual observer/lifecycle assertions, including synchronous own-acquire delivery before Task creation`);
});

test('release observer regression rejects synchronous own-acquire reentry without the waiting latch', {timeout: 60000}, async () => {
    await assert.rejects(execute((dir, marker) => buildChat(dir, marker, source => {
        const guard = 'if not m.animationStorageObserved then return';
        assert.equal(source.split(guard).length, 2);
        return source.replace(guard, 'if false then return');
    }, 'testStorageWaiterLifecycle'), true), /synchronous own-acquire callback cannot reenter admission: workers=2/);
});

test('release observer cleanup regression detects callbacks still subscribed after hide or disposal', {timeout: 60000}, async () => {
    await assert.rejects(execute((dir, marker) => buildChat(dir, marker, source => {
        const cleanup = 'm.global.unobserveFieldScoped("chatAnimationStorageOwners")';
        assert.equal(source.split(cleanup).length, 2);
        return source.replace(cleanup, "' cleanup disabled by regression probe");
    }, 'testStorageWaiterLifecycle'), true), /hidden and disposed Chats receive no global release callbacks after scoped cleanup/);
});

test('release notification regression rejects a ledger release without notifying visible waiting Chats', {timeout: 60000}, async () => {
    await assert.rejects(execute((dir, marker) => buildChat(dir, marker, source => {
        const observe = 'm.global.observeFieldScoped("chatAnimationStorageOwners", "onChatAnimationStorageOwners")';
        assert.equal(source.split(observe).length, 2);
        return source.replace(observe, "' release notification disabled by regression probe");
    }, 'testSharedOwnership'), true), /visible waiting Chat wakes automatically after acknowledged ownership release/);
});

test('global reservation regression rejects admitting another Chat while a disposed worker drains', {timeout: 60000}, async () => {
    await assert.rejects(execute((dir, marker) => buildChat(dir, marker, source => {
        const guard = 'if not reserveChatAnimationStorage() then return';
        assert.equal(source.split(guard).length, 2);
        return source.replace(guard, 'if false then return');
    }, 'testSharedOwnership'), true), /disposed draining worker must reserve global admission: workers=2 files=2/);
});

test('one-slot regression fixture rejects restarting the animation on each new message', {timeout: 60000}, async () => {
    await assert.rejects(execute((dir, marker) => buildChat(dir, marker, source => {
        assert.equal(source.split('if candidates.ownerVisible\n').length, 2);
        return source.replace('if candidates.ownerVisible\n', 'if false\n');
    }), true), /new messages and duplicate URIs cannot restart or hop the active owner/);
});

test('handoff regression fixture rejects consuming a response before the producer Task returns', {timeout: 60000}, async () => {
    await assert.rejects(execute((dir, marker) => buildChat(dir, marker, source => source
        .replace('observeField("state", "onChatAnimationAsset")', 'observeField("response", "onChatAnimationAsset")')
        .replace('if state <> "stop" and state <> "done" then return', 'if false then return')),
    true), /render waits for real thread termination before file handoff/);
});
