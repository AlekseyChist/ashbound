// Repository QA for the supported PO/POT syntax, coverage, forms and parameters.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const expected = [
  'UI_LANGUAGE', 'UI_LANGUAGE_AUTO', 'UI_CLOSE', 'UI_ACTION_INTERACT',
  'UI_ACTION_ATTACK', 'UI_ACTION_RUN', 'UI_ACTION_WALK', 'UI_GREETING', 'UI_ITEM_COUNT',
];
const failures = [];
const check = (ok, message) => { if (!ok) failures.push(message); };
const placeholders = text => [...new Set([...text.matchAll(/\{([A-Za-z_][A-Za-z_0-9]*)\}/g)].map(m => m[1]))].sort();

function parse(file) {
  const entries = new Map();
  let entry = {}, field = null;
  function flush() {
    if (!Object.hasOwn(entry, 'msgid')) return;
    const key = `${entry.msgctxt || ''}\x04${entry.msgid}`;
    check(!entries.has(key), `${file}: duplicate ${entry.msgid}`);
    entries.set(key, entry);
    entry = {};
    field = null;
  }
  fs.readFileSync(path.join(root, 'localization', file), 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/).forEach((line, index) => {
    const text = line.trim();
    if (!text) { flush(); return; }
    if (text.startsWith('#')) {
      check(!/^#,.*\bfuzzy\b/.test(text), `${file}:${index + 1}: fuzzy translation`);
      return;
    }
    const match = text.match(/^(msgctxt|msgid_plural|msgid|msgstr(?:\[\d+\])?)\s+(".*")$/);
    try {
      if (match) {
        if (match[1] === 'msgid' && Object.hasOwn(entry, 'msgid')) flush();
        field = match[1];
        check(!Object.hasOwn(entry, field), `${file}:${index + 1}: repeated ${field}`);
        entry[field] = JSON.parse(match[2]);
      } else if (text.startsWith('"') && field) {
        entry[field] += JSON.parse(text);
      } else {
        failures.push(`${file}:${index + 1}: unsupported PO syntax`);
      }
    } catch (error) { failures.push(`${file}:${index + 1}: ${error.message}`); }
  });
  flush();
  return entries;
}

for (const [file, locale, forms] of [['en.po', 'en', 2], ['ru.po', 'ru', 3], ['messages.pot', '', 2]]) {
  const entries = parse(file);
  const header = entries.get('\x04')?.msgstr ?? '';
  check(header.includes('charset=UTF-8'), `${file}: UTF-8 header`);
  if (locale) {
    check(header.includes(`Language: ${locale}\n`), `${file}: language header`);
    check(header.includes(`nplurals=${forms};`), `${file}: plural count header`);
  }
  const messages = [...entries.values()].filter(entry => entry.msgid !== '');
  check(JSON.stringify(messages.map(e => e.msgid).sort()) === JSON.stringify([...expected].sort()), `${file}: complete nine-key registry`);
  for (const entry of messages) {
    check(!entry.msgctxt, `${file}: unexpected context for ${entry.msgid}`);
    const plural = entry.msgid === 'UI_ITEM_COUNT';
    check((entry.msgid_plural ?? '') === (plural ? 'UI_ITEM_COUNTS' : ''), `${file}: plural key ${entry.msgid}`);
    const wantedFields = plural ? Array.from({ length: forms }, (_, i) => `msgstr[${i}]`) : ['msgstr'];
    check(JSON.stringify(Object.keys(entry).filter(k => k.startsWith('msgstr')).sort()) === JSON.stringify(wantedFields.sort()), `${file}: indexed forms ${entry.msgid}`);
    for (const field of wantedFields) {
      const text = entry[field];
      check(typeof text === 'string', `${file}: missing ${field} for ${entry.msgid}`);
      if (typeof text !== 'string') continue;
      check(locale ? text.trim().length > 0 : text === '', `${file}: ${locale ? 'empty translation' : 'nonempty template'} ${entry.msgid}`);
      if (locale) {
        const wanted = plural ? ['count'] : entry.msgid === 'UI_GREETING' ? ['name'] : [];
        check(JSON.stringify(placeholders(text)) === JSON.stringify(wanted), `${file}: placeholders ${entry.msgid}/${field}`);
      }
    }
  }
}
if (failures.length) {
  failures.forEach(failure => console.error(`CATALOG_FAIL: ${failure}`));
  process.exitCode = 1;
} else {
  console.log('ASHBOUND_LOCALIZATION_CATALOGS_OK keys=9 locales=2');
}
