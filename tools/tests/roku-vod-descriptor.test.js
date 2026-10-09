'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { fixture, positive, normal, run } = require('./fixtures/roku-vod-descriptor/support');
const os = require('node:os');
const { randomUUID } = require('node:crypto');

const origin = 'https://dfixture123.cloudfront.net';
const source = `${origin}/archive/index.m3u8?sig=fixture%2B%25`;
const usher = 'https://usher.ttvnw.net/vod/v2/123456.m3u8?token=fixture%2B%25';
const attrs = 'BANDWIDTH=6000000,CODECS="avc1.4D402A,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=60.000,VIDEO="chunked"';
const master = `#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-STREAM-INF:${attrs}\n${source}\n`;
const base = { origin, source, usher, master };
const bad = [];
const add = (name, changes) => bad.push({ name, master, usher, source, id: '123456', quality: '1080p60 (Source)', ...changes });
add('wrong Usher host', { usher: usher.replace('usher.ttvnw.net', 'foreign.ttvnw.net') });
add('wrong VOD path', { usher: usher.replace('123456.m3u8', '123457.m3u8') });
add('encoded Usher path', { usher: usher.replace('/vod/', '/%76od/') });
add('wrong source query bytes', { source: source.replace('%2B', '%2b') });
add('source absent from master', { master: master.replace(source, `${origin}/other.m3u8`) });
add('duplicate matching rendition', { master: master + `#EXT-X-STREAM-INF:${attrs}\n${source}\n` });
add('wrong display quality', { quality: '720p' });
add('automatic is not fixed rendition', { quality: 'Automatic' });
add('zero identifier', { id: '0' });
add('leading zero identifier', { id: '0123456' });
add('numeric identifier type', { id: 123456 });
add('unknown stream attribute', { master: master.replace('BANDWIDTH=', 'FOREIGN=1,BANDWIDTH=') });
add('duplicate stream attribute', { master: master.replace('BANDWIDTH=', 'BANDWIDTH=2,BANDWIDTH=') });
add('unfinished rendition', { master: master.replace(source + '\n', '') });
add('unknown required tag', { master: master + '#EXT-X-SESSION-KEY:METHOD=AES-128\n' });
add('bad first line', { master: master.replace('#EXTM3U', '#EXTM3X') });
add('non ASCII master', { master: master + '\u0080' });
add('oversized master', { master: 'x'.repeat(262145) });
add('excess master lines', { master: master + '\n'.repeat(2048) });
add('overlong line', { master: master + '#'.repeat(8193) });
add('unsupported HEVC', { master: master.replace('avc1.4D402A', 'hvc1.1.6.L120') });
add('above 1080p', { master: master.replace('1920x1080', '2560x1440') });
add('above finite FPS', { master: master.replace('60.000', '60.011') });
add('unsupported audio', { master: master.replace('mp4a.40.2', 'opus') });
add('separate audio', { master: master.replace('#EXT-X-STREAM-INF:', '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="A",URI="https://foreign.example.test/a.m3u8"\n#EXT-X-STREAM-INF:AUDIO="audio",') });
for (const [name, url] of [
    ['foreign CDN', 'https://foreign.example.test/a.m3u8'], ['wild CloudFront', 'https://arbitrary.cloudfront.net/a.m3u8'],
    ['encoded origin', 'https://d%66ixture123.cloudfront.net/a.m3u8'], ['userinfo', 'https://user@dfixture123.cloudfront.net/a.m3u8'],
    ['port', 'https://dfixture123.cloudfront.net:443/a.m3u8'], ['IP', 'https://127.0.0.1/a.m3u8'],
    ['uppercase', 'https://DFIXTURE123.cloudfront.net/a.m3u8'], ['traversal', `${origin}/../a.m3u8`],
    ['fragment', `${source}#a`], ['backslash', `${origin}/a\\b.m3u8`]
]) add(name, { source: url, master: master.replace(source, url) });
const inputs = () => ({ 'data.json': JSON.stringify({ ...base, bad }) });

test('actual VOD descriptor derives exact bounded hints and corroborates one trusted rendition', { timeout: 90000 }, async t => {
    const { result, marker } = await fixture('roku-vod-descriptor', 'normal', inputs());
    t.diagnostic(`${positive(result, marker)} actual pure descriptor assertions; no remote provenance/transport claim`);
});
test('actual descriptor wrong-provenance and ambiguous-rendition mutants cannot pass', { timeout: 210000 }, async t => {
    for (const [before, after, label] of [
        ['if matches > 1 then return invalid', 'if matches > 1 then matches = 1', 'refuse duplicate matching rendition'],
        ['return parsed.origin = "https://usher.ttvnw.net" and parsed.path = "/vod/v2/" + vodId + ".m3u8"', 'return true', 'refuse wrong Usher host'],
        ['if descriptor.metadata[key] <> rebuilt.metadata[key] then return false', "' Deliberately trust claimed hints", 'valid syntax alone cannot establish master provenance']
    ]) {
        const { result, marker } = await fixture('roku-vod-descriptor', 'normal', inputs(), { name: 'rokuVodDescriptor', before, after });
        normal(result);
        assert.ok(result.output.includes(`VOD_P2_FAIL: ${label}`), result.output);
        assert.throws(() => positive(result, marker));
        t.diagnostic(`${label}: actual normal-exit mutation rejected`);
    }
});
test('pure P2 runner rejects stale,duplicate,zero,failure,crash and bounded transport faults', { timeout: 15000 }, async () => {
    const marker = randomUUID();
    const text = `VOD_P2_RESULT: ${marker} {"assertions":1,"failures":0}\n`;
    const shaped = output => ({ code: 0, output, timedOut: false, exceeded: false });
    positive(shaped(text), marker);
    for (const output of [text.replace(marker, randomUUID()), text + text, text.replace('"assertions":1', '"assertions":0'), text.replace('"failures":0', '"failures":1'), text + 'VOD_P2_FAIL: x\n', text + 'BRIGHTSCRIPT: ERROR: x\n']) assert.throws(() => positive(shaped(output), marker));
    const timeout = await run(['-e', 'setInterval(() => {},100);'], os.tmpdir(), 150, 1024);
    assert.ok(timeout.timedOut);
    assert.throws(() => positive(timeout, marker));
    const overflow = await run(['-e', 'process.stdout.write("x".repeat(2048));'], os.tmpdir(), 2000, 1024);
    assert.ok(overflow.exceeded);
    assert.throws(() => positive(overflow, marker));
    assert.throws(() => positive({ ...shaped(text), code: 7 }, marker));
});
