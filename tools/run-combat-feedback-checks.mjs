// Codex independent QA. Stage imports through the existing verified copier.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root = path.resolve(import.meta.dirname, '..');
const stage = path.join(root, '.tools/export-staging/corner-enemy-checks');
execFileSync(process.execPath, ['tools/run-corner-enemy-checks.mjs', '--import-only'], {cwd:root, windowsHide:true, stdio:'inherit'});
const godot = process.env.ASHBOUND_GODOT || path.join(root,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
for (const script of ['combat_feedback_fx','combat_feedback_player','combat_feedback_session','combat_feedback_sandbox','validate_combat_feedback']) {
 const result = execFileSync(godot,['--headless','--path',stage,'--check-only','--script',`res://scripts/tools/${script}.gd`],{windowsHide:true,timeout:20000,encoding:'utf8',stdio:['ignore','pipe','pipe']});
 if (/SCRIPT ERROR:|^ERROR:/m.test(result)) throw Error(`Parse check failed: ${script}`);
}
for (const render of process.argv.includes('--headless-only') ? [false] : [false,true]) {
 const name = render ? 'render' : 'core';
 const log = path.join(root, `.tools/feedback-${name}.log`);
 const fd = fs.openSync(log,'w'); let failure;
 try {execFileSync(godot,['--path',stage,...(render ? ['--windowed','--resolution','1600x900','--position','-10000,-10000'] : ['--headless']), 'res://scripts/tools/validate_combat_feedback.tscn'],{windowsHide:true,timeout:120000,stdio:['ignore',fd,fd]});}
 catch(e){failure=e;}finally{fs.closeSync(fd);}
 const out = fs.readFileSync(log,'utf8');
 if(failure || /SCRIPT ERROR:|^ERROR:/m.test(out) || !out.includes('ASHBOUND_COMBAT_FEEDBACK_OK groups=9')) {
   console.log(out.slice(-16000)); throw Error(log);
 }
 console.log(`PASS feedback ${name}`);
}
console.log('ASHBOUND_COMBAT_FEEDBACK_CHECKS_OK');
