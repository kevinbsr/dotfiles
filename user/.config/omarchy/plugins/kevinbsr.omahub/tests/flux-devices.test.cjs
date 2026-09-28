const assert = require('node:assert/strict');
const test = require('node:test');
const model = require('../flux/FluxModel.js');

// Shapes taken from a real `flux status --json` (fluxd 0.4.0), trimmed to the
// fields this reads.
const phone = (over = {}) => Object.assign({
  id: '554ffce13b5e42fb9de2b2a97f6bbdaa',
  name: 'Galaxy S23 Ultra',
  type: 'phone',
  paired: true,
  online: true,
  pairState: 'paired',
  pairKey: '',
  battery: { charge: 25, charging: true },
}, over);

test('devices survive a status with nothing in it', () => {
  assert.deepEqual(model.devices(null), []);
  assert.deepEqual(model.devices({}), []);
  assert.deepEqual(model.devices({ devices: 'not a list' }), []);
  assert.deepEqual(model.devices({ devices: [{ id: 'x' }] }), []); // no name, no row
});

test('the phone in use sorts above the ones that are not', () => {
  const list = model.devices({
    devices: [
      phone({ name: 'Old tablet', paired: false, online: false }),
      phone({ name: 'Spare phone', paired: true, online: false }),
      phone({ name: 'Galaxy S23 Ultra' }),
      phone({ name: 'A laptop', paired: false, online: true }),
    ],
  });
  assert.deepEqual(list.map(d => d.name),
    ['Galaxy S23 Ultra', 'Spare phone', 'A laptop', 'Old tablet']);
});

test('only a paired, reachable device offers actions', () => {
  assert.equal(model.usable(phone()), true);
  assert.equal(model.usable(phone({ online: false })), false);
  assert.equal(model.usable(phone({ paired: false })), false);
  assert.equal(model.usable(null), false);
});

test('the subtitle says the state first and the battery after', () => {
  assert.equal(model.deviceSubtitle(phone()), 'connected · 25% charging');
  assert.equal(model.deviceSubtitle(phone({ battery: { charge: 80, charging: false } })),
    'connected · 80%');
  assert.equal(model.deviceSubtitle(phone({ online: false })), 'offline · 25% charging');
  assert.equal(model.deviceSubtitle(phone({ paired: false, pairState: 'requested' })),
    'wants to pair · 25% charging');
  assert.equal(model.deviceSubtitle(phone({ type: 'desktop' })),
    'connected · 25% charging · desktop');
});

test('a device with no battery reported says nothing about one', () => {
  assert.equal(model.deviceSubtitle(phone({ battery: null })), 'connected');
  assert.equal(model.deviceSubtitle(phone({ battery: {} })), 'connected');
  assert.equal(model.batteryText(phone({ battery: { charge: '25' } })), '');
});

test('a name is always drawn, even for a device that barely answered', () => {
  assert.equal(model.deviceTitle({ name: 'Pixel 8' }), 'Pixel 8');
  assert.equal(model.deviceTitle({}), 'Unknown device');
  assert.equal(model.deviceTitle(null), 'Unknown device');
});

test('pending pairing is the one device waiting on a decision', () => {
  assert.equal(model.pendingPairing([phone(), phone({ name: 'B', online: false })]), null);
  assert.equal(model.pendingPairing([]), null);
  assert.equal(model.pendingPairing(null), null);

  const waiting = phone({ name: 'Pixel 8', paired: false, pairState: 'requested', pairKey: '8D391034' });
  assert.equal(model.pendingPairing([phone(), waiting]).name, 'Pixel 8');

  // A device that is simply not paired is not a request to act on.
  assert.equal(model.pendingPairing([phone({ paired: false, pairState: 'none' })]), null);
  assert.equal(model.pendingPairing([phone({ paired: false, pairState: 'unpaired' })]), null);
});

// ---- The shared clipboard.

test('clipboard entries keep their order and drop the empty ones', () => {
  const state = { clipboard: [
    { text: 'one', dir: 'out', deviceName: 'this pc', time: 30 },
    { text: '', dir: 'in', deviceName: 'phone', time: 20 },
    { text: 'two', dir: 'in', deviceName: 'Galaxy', time: 10 },
    { text: 'three', dir: 'out', time: 5 },
  ] };
  assert.deepEqual(model.clipboard(state, 2).map(c => c.text), ['one', 'two']);
  assert.deepEqual(model.clipboard(null), []);
  assert.deepEqual(model.clipboard({ clipboard: 'nope' }), []);
});

test('the clipboard meta says which side copied it', () => {
  const now = 100;
  assert.equal(model.clipboardMeta({ text: 'x', dir: 'in', deviceName: 'Galaxy', time: 40 }, now),
    'from Galaxy · 1m');
  assert.equal(model.clipboardMeta({ text: 'x', dir: 'out', time: 40 }, now),
    'from this computer · 1m');
  assert.equal(model.clipboardMeta({ text: 'x', dir: 'in', time: 0 }, now), 'from the phone');
  assert.equal(model.clipboardMeta(null, now), '');
});

// ---- The payloads, pinned to what Flux's own CLI sends.
//
// Captured by pointing `flux` at a stand-in socket that logged the request and
// answered with an empty result, so nothing reached the phone. If fluxd ever
// renames a field, these fail here instead of failing silently on someone's
// desk.

const dev = { id: '554ffce13b5e42fb9de2b2a97f6bbdaa', name: 'Galaxy S23 Ultra' };

test('ping carries the device and the message', () => {
  assert.deepEqual(model.pingParams(dev, 'oi'),
    { device: dev.id, message: 'oi' });
  assert.deepEqual(model.pingParams(null, null), { device: '', message: '' });
});

test('share.url carries the url', () => {
  assert.deepEqual(model.urlParams(dev, 'https://example.com'),
    { device: dev.id, url: 'https://example.com' });
});

test('clipboard.send omits text to mean the current clipboard', () => {
  assert.deepEqual(model.clipboardParams(dev), { device: dev.id });
  assert.deepEqual(model.clipboardParams(dev, ''), { device: dev.id });
  assert.deepEqual(model.clipboardParams(dev, 'copiado'),
    { device: dev.id, text: 'copiado' });
});

test('sms.send takes a list of addresses and a body', () => {
  assert.deepEqual(model.smsParams(dev, '+5522999999999', 'oi'),
    { device: dev.id, addresses: ['+5522999999999'], body: 'oi' });
});

test('share.files takes paths, and drops the empty ones', () => {
  assert.deepEqual(model.filesParams(dev, ['/tmp/a.txt', '', '/tmp/b.txt']),
    { device: dev.id, paths: ['/tmp/a.txt', '/tmp/b.txt'] });
  assert.deepEqual(model.filesParams(dev, null), { device: dev.id, paths: [] });
});

test('a link goes to the browser, anything else arrives as text', () => {
  assert.equal(model.shareMethod('https://omarchy.org'), 'share.url');
  assert.equal(model.shareMethod('  http://x.test  '), 'share.url');
  assert.equal(model.shareMethod('magnet:?xt=urn:btih:abc'), 'share.url');
  assert.equal(model.shareMethod('mailto:a@b.c'), 'share.url');
  assert.equal(model.shareMethod('lembrar de comprar pão'), 'share.text');
  assert.equal(model.shareMethod('omarchy.org'), 'share.text'); // sem esquema, não é link
  assert.equal(model.shareMethod(''), 'share.text');
  assert.deepEqual(model.textParams({ id: 'abc' }, 'oi'), { device: 'abc', text: 'oi' });
});

test('unpair carries the device', () => {
  assert.deepEqual(model.unpairParams({ id: 'abc' }), { device: 'abc' });
});

test('a button is only drawn for something the phone says it can do', () => {
  const phone6 = { plugins: ['battery', 'clipboard', 'findmyphone', 'notifications', 'runcommand', 'share'] };
  assert.equal(model.supports(phone6, 'ring'), true);
  assert.equal(model.supports(phone6, 'clipboard'), true);
  assert.equal(model.supports(phone6, 'share'), true);
  assert.equal(model.supports(phone6, 'sms'), false);   // this phone does not advertise sms
  assert.equal(model.supports(phone6, 'ping'), true);   // no plugin of its own

  // A device that advertises nothing at all is given the benefit of the doubt:
  // hiding every button over a missing field would be worse than a click that
  // does nothing.
  assert.equal(model.supports({}, 'sms'), true);
  assert.equal(model.supports({ plugins: [] }, 'sms'), true);
  assert.equal(model.supports(null, 'sms'), true);
  assert.equal(model.supports({ plugins: ['sms'] }, 'sms'), true);
});
