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

// ---- What the phone is showing, and the shared clipboard.

const note = (over = {}) => Object.assign({
  id: '0|com.whatsapp|1|abc|10361',
  app: 'WhatsApp',
  title: 'A group',
  text: 'a message',
  time: 1790565216,
  replyId: '',
  actions: [],
  dismissable: true,
}, over);

test('notifications come back newest first and capped', () => {
  const device = { notifications: [
    note({ time: 100, title: 'old' }),
    note({ time: 300, title: 'newest' }),
    note({ time: 200, title: 'middle' }),
  ] };
  assert.deepEqual(model.notifications(device, 2).map(n => n.title), ['newest', 'middle']);
  assert.equal(model.notificationCount(device), 3);
});

test('a notification with neither title nor text is not a row', () => {
  const device = { notifications: [note({ title: '', text: '' }), note()] };
  assert.equal(model.notifications(device).length, 1);
});

test('devices with no notifications at all do not throw', () => {
  assert.deepEqual(model.notifications(null), []);
  assert.deepEqual(model.notifications({}), []);
  assert.deepEqual(model.notifications({ notifications: 'nope' }), []);
  assert.equal(model.notificationCount({ notifications: 'nope' }), 0);
});

test('the meta line is the app and how long ago', () => {
  const now = 1790565216 + 600;
  assert.equal(model.notificationMeta(note(), now), 'WhatsApp · 10m');
  assert.equal(model.notificationMeta(note({ app: '' }), now), '10m');
  assert.equal(model.notificationMeta(note({ time: 0 }), now), 'WhatsApp');
  assert.equal(model.notificationMeta(null, now), '');
});

test('time ago stays coarse and never goes negative', () => {
  const now = 1000000;
  assert.equal(model.timeAgo(now - 5, now), 'now');
  assert.equal(model.timeAgo(now - 90, now), '1m');
  assert.equal(model.timeAgo(now - 7200, now), '2h');
  assert.equal(model.timeAgo(now - 200000, now), '2d');
  assert.equal(model.timeAgo(now + 500, now), 'now'); // a clock that disagrees
  assert.equal(model.timeAgo(0, now), '');
  assert.equal(model.timeAgo('nope', now), '');
});

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
