import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';

// Exercise the actual bridge function boundary resolver without starting Ollama.
const source = await fs.readFile(new URL('./ollama-godot.mjs', import.meta.url), 'utf8');
const start = source.indexOf('function functionRange(');
const end = source.indexOf('async function fileTool(', start);
assert(start >= 0 && end > start);
const rangeOf = vm.runInNewContext(`(${source.slice(start, end).trim()})`);
const gd = 'extends Node\n\nfunc alpha() -> void:\n\tprint("a")\n\t# body comment\n\n\n# following documentation\nfunc beta() -> void:\n\tpass\n';
const range = rangeOf(gd, 'alpha');
assert.equal(range.content, 'func alpha() -> void:\n\tprint("a")\n\t# body comment');
const replaced = gd.slice(0, range.start) + 'func alpha() -> void:\n\tpass\n\n' + gd.slice(range.end);
assert(replaced.startsWith('extends Node\n\nfunc alpha'));
assert(replaced.endsWith('# following documentation\nfunc beta() -> void:\n\tpass\n'));
const staticSource = 'static func plan(x):\r\n\treturn x\r\n\r\nvar after = 4\r\n';
const staticRange = rangeOf(staticSource, 'plan');
assert.equal(staticRange.content, 'static func plan(x):\r\n\treturn x');
assert.equal(staticSource.slice(staticRange.end), 'var after = 4\r\n');
assert.throws(() => rangeOf(gd, 'missing'), /exactly once/);
assert.throws(() => rangeOf(gd + '\nfunc alpha():\n\tpass\n', 'alpha'), /exactly once/);
assert.throws(() => rangeOf(gd, 'alpha.*'), /Invalid function/);
assert.equal(rangeOf('func only():\n\tpass', 'only').end, 18);
console.log('OLLAMA_FUNCTION_EDIT_OK: function boundaries preserve surrounding code; unsafe names and ambiguity rejected');
