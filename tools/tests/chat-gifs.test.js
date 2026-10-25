'use strict';

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {randomUUID} = require('node:crypto');
const {spawn} = require('node:child_process');
const {zipFolder} = require('roku-deploy');
const corpus = require('./fixtures/chat-gifs/corpus');
const webp = require('./fixtures/chat-animation/corpus');
const root = path.resolve(__dirname, '../..');
const cli = path.join(root, 'node_modules/brs-node/bin/brs.cli.js');
const fixtures = path.join(__dirname, 'fixtures/chat-gifs');

async function add(dir, name, data) {
    const file = path.join(dir, name);
    await fs.mkdir(path.dirname(file), {recursive:true});
    await fs.writeFile(file, data);
}
async function execute(build, sceneGraph = false) {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'stitch-gif-'));
    const marker = `GIF_PASS_${randomUUID()}`;
    try {
        await build(dir, marker);
        const sources = (await fs.readdir(dir)).filter(file => file.endsWith('.brs'));
        let args = [cli, '--no-sg', '--root', dir, ...sources];
        if (sceneGraph) {
            const zip = path.join(dir, 'app.zip');
            await zipFolder(path.join(dir, 'package'), zip);
            args = [path.join(__dirname, 'fixtures/ui-startup-player/key-driver.js'), cli, zip];
        }
        const result = await new Promise((resolve, reject) => {
            const child = spawn(process.execPath, args, {cwd:dir,windowsHide:true});
            let output = '', timedOut = false;
            const timer = setTimeout(() => {timedOut=true; child.kill();}, 45000);
            const collect = data => {output+=data; if(output.length>1024*1024) child.kill();};
            child.stdout.on('data',collect); child.stderr.on('data',collect);
            child.on('error',reject);
            child.on('close',code => {clearTimeout(timer);resolve({code,output,timedOut});});
        });
        assert.equal(result.timedOut,false,result.output.slice(-10000));
        assert.equal(result.code,0,result.output.slice(-10000));
        assert.doesNotMatch(result.output,/STITCH_TEST_FAIL:|runtime error|BrightScript Debugger|EXIT_BRIGHTSCRIPT_CRASH|unhandled exception|failed to set up component/i);
        if (sceneGraph) assert.match(result.output, /EXIT_USER_NAV/);
        const count=result.output.match(new RegExp(`${marker}:\\s*(\\d+) assertions`));
        assert.ok(count && Number(count[1])>0,`fresh nonzero summary required\n${result.output.slice(-10000)}`);
        return Number(count[1]);
    } finally {
        assert.equal(path.dirname(path.resolve(dir)),path.resolve(os.tmpdir()));
        assert.ok(path.basename(dir).startsWith('stitch-gif-'));
        await fs.rm(dir,{recursive:true,force:true});
    }
}
async function helpers(dir, names) {
    for(const name of names) await add(dir,`${name}.brs`,await fs.readFile(path.join(root,`source/utils/${name}.brs`)));
}
test('actual Twitch GIF parser preserves documented URLs/titles and validates bounded code-point occurrences', async t => {
    const count=await execute(async (dir,marker) => {
        await helpers(dir,['ircParser','ircEmotes','ircGifs']);
        const main=await fs.readFile(path.join(root,'source/tests/offline/chat-gifs.brs'),'utf8');
        await add(dir,'main.brs',main.replace('STITCH_TEST_PASS: chat-gifs ',`${marker}: `));
    });
    t.diagnostic(`${count} actual BrightScript wire/parser assertions; Unicode and negative cases are authored fixtures`);
});
test('actual GIF structural admission accepts the pinned public sample and rejects malformed/budget mutations', async t => {
    const count=await execute(async (dir,marker) => {
        await helpers(dir,['chatAnimationGif']);
        await add(dir,'main.brs',(await fs.readFile(path.join(fixtures,'admission-main.brs'),'utf8')).replace('__PASS_MARKER__',marker));
        await add(dir,'cases.json',JSON.stringify(corpus.cases.map(({bytes,...sample})=>sample)));
        for(const sample of corpus.cases) await add(dir,`${sample.name}.gif`,sample.bytes);
    });
    t.diagnostic(`${count} actual structural assertions; no LZW decode or native playback proof`);
});
test('actual GIF Task preserves URL, requires HEAD/GET/final stat, bounds time, and cleans cancellations', async t => {
    const count=await execute(async (dir,marker) => {
        await helpers(dir,['chatAnimationGif','chatAnimationWebp','ircEmotes','ircGifs']);
        const source=await fs.readFile(path.join(root,'components/Modules/Chat/ChatAnimationAsset/ChatAnimationAsset.brs'),'utf8');
        assert.equal((source.match(/\bfs\.stat\(/g)||[]).length,2,'only polling and final stat are explicit boundaries');
        await add(dir,'task.brs',source.replace(/\bcreateObject\("(roFileSystem|roMessagePort|roTimespan|roUrlTransfer|roByteArray)"\)/gi,'fixtureCreateObject("$1")')
            .replace(/\bwait\(/gi,'fixtureWait(').replace('type(event) = "roUrlEvent"','fixtureIsUrlEvent(event)')
            .replace(/\bfs\.stat\(([^)]*)\)/g,'fixtureStat(fs, $1)'));
        await add(dir,'main.brs',(await fs.readFile(path.join(fixtures,'asset-main.brs'),'utf8')).replace('__PASS_MARKER__',marker));
        await add(dir,'tiny.gif',corpus.tiny);
        await add(dir,'twitch-official.gif',corpus.official);
        await add(dir,'petpet.webp',webp.petpet);
    });
    t.diagnostic(`${count} actual Task/filesystem assertions with HTTP/clock and pending metadata boundaries; not a network hard cap`);
});
test('actual animation manager accepts Group fallback, auto-detects GIF, and restores text on native error', async t => {
    const count=await execute(async (dir,marker) => {
        const pkg=path.join(dir,'package');
        await add(pkg,'manifest','title=GIF Manager Contract Fixture\nmajor_version=1\nminor_version=0\nbuild_version=0\nui_resolutions=hd\n');
        await add(pkg,'source/main.brs',await fs.readFile(path.join(fixtures,'manager-main.brs')));
        await add(pkg,'components/manager-scene.brs',(await fs.readFile(path.join(fixtures,'manager-scene.brs'),'utf8')).replace('__PASS_MARKER__',marker));
        const source=await fs.readFile(path.join(root,'components/Modules/Chat/ChatAnimations.brs'),'utf8');
        await add(pkg,'components/ChatAnimations.brs',source.replace('createObject("roSGNode", nodeType)','createObject("roSGNode", "AnimatedImageBoundary")')
            .replace('createObject("roSGNode", "ChatAnimationAsset")','fixtureAssetTask()'));
        for (const helper of ['ircGifs','ircEmotes','taskFactory']) await add(pkg,`source/utils/${helper}.brs`,await fs.readFile(path.join(root,`source/utils/${helper}.brs`)));
        await add(pkg,'components/AnimatedImageBoundary.xml',await fs.readFile(path.join(__dirname,'fixtures/chat-animation/AnimatedImageBoundary.xml')));
        await add(pkg,'components/GifManagerFixture.xml','<component name="GifManagerFixture" extends="Scene"><interface><function name="runFixture" /></interface>'+
            '<script uri="manager-scene.brs" /><script uri="ChatAnimations.brs" />'+
            '<script uri="pkg:/source/utils/ircGifs.brs" /><script uri="pkg:/source/utils/ircEmotes.brs" /><script uri="pkg:/source/utils/taskFactory.brs" /></component>');
    },true);
    t.diagnostic(`${count} actual manager assertions with scripted native states; no GIF decoding or visible motion proof`);
});
