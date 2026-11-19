const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const instruction = Buffer.alloc(4);
instruction.writeUInt32LE((0xd4200000 | (0xf00d << 5)) >>> 0);
const brk = instruction.toString('hex');
let commands = [];
let prepared = [];
let allocation = '7000000000';
let preparation = 'OK';
let registerWrite = 'OK';
const context = vm.createContext({
    get_pid: () => 42,
    log: () => {},
    send_command(command) {
        commands.push(command);
        if (command === 'c') {
            return 'T05thread:1;20:0000010000000000;10:0000000000000000;00:0000000000000000;01:0000000000000000;';
        }
        if (command.startsWith('m')) return brk;
        if (command.startsWith('_M')) return allocation;
        if (command.startsWith('P0=')) return registerWrite;
        return 'OK';
    },
    prepare_memory_region(address, length) {
        assert.equal(typeof address, 'number');
        assert.equal(typeof length, 'number');
        prepared.push([address, length]);
        return preparation;
    },
});
const resources = path.join(__dirname, '../Natives/resources');
// The initial synthetic BRK requests detach so the real top-level loop exits.
vm.runInContext(fs.readFileSync(path.join(resources, 'UniversalJIT26.js'), 'utf8'), context);
vm.runInContext(fs.readFileSync(path.join(resources, 'UniversalJIT26Extension.js'), 'utf8'), context);
function reset() {
    commands = [];
    prepared = [];
    vm.runInContext("pc = 0x10000n; tid = '1'; x0 = 0n; x1 = 0x8000n;", context);
}
function prepare() { vm.runInContext('JIT26PrepareRegion()', context); }

reset();
prepare();
assert.deepEqual(prepared, [[0x7000000000, 0x8000]]);
assert(commands.includes('P0=0000000070000000;thread:1;'));
reset();
vm.runInContext('x0 = 0x7007534000n', context);
prepare();
assert.deepEqual(prepared, [[0x7007534000, 0x8000]]);
assert(commands.includes('P0=0040530770000000;thread:1;'));
assert(!commands.some(command => command.startsWith('_M')));

for (allocationError of ['E01', '', '0', 'not-an-address']) {
    reset();
    allocation = allocationError;
    assert.throws(prepare, /Failed to allocate RX memory/);
    assert.equal(prepared.length, 0);
    assert(!commands.some(command => command.startsWith('P0=')));
}
allocation = '7000000000';
for (preparationError of ['E01', '']) {
    reset();
    preparation = preparationError;
    assert.throws(prepare, /Failed to prepare JIT memory/);
    assert(!commands.some(command => command.startsWith('P0=')));
    // The legacy JVM command must also avoid detaching after a failed write.
    reset();
    vm.runInContext('detachAfterFirstBr = true; x0 = 0x8000n', context);
    assert.throws(() => vm.runInContext('legacyCommands[0x69]()', context), /Failed to prepare JIT memory/);
    assert(!commands.includes('D'));
}
preparation = 'OK';
registerWrite = 'E01';
reset();
assert.throws(prepare, /Failed to return JIT memory address/);
registerWrite = 'OK';
reset();
vm.runInContext('detachAfterFirstBr = true; x0 = 0x8000n; legacyCommands[0x69]()', context);
assert(commands.indexOf('D') > commands.findIndex(command => command.startsWith('P0=')));
console.log('Universal JIT high address and failure tests passed');
