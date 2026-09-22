// Codex QA: strict logs, full scenario completion, and previous preview regression.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const stage=path.join(root,'.tools/export-staging/corner-enemy-checks');
const godot=process.env.ASHBOUND_GODOT || path.join(root,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
execFileSync(process.execPath,['tools/run-corner-enemy-checks.mjs','--import-only'],{cwd:root,windowsHide:true,stdio:'inherit'});
function run(name,args,marker,timeout=120000){
 const log=path.join(root,`.tools/${name}.log`),fd=fs.openSync(log,'w'); let failure;
 try{execFileSync(godot,['--path',stage,...args],{windowsHide:true,timeout,stdio:['ignore',fd,fd]});}
 catch(e){failure=e;}finally{fs.closeSync(fd);}
 const out=fs.readFileSync(log,'utf8');
 if(failure || /SCRIPT ERROR:|^ERROR:|FEEDBACK_FAIL:|INCOMPLETE|TIMEOUT/m.test(out) || (marker && !out.includes(marker))){console.log(out.slice(-18000));throw Error(log);}
 console.log('PASS '+name);
}
// Sandbox depends on project autoloads, so compile it through its real scene below.
for(const script of ['attack_frame_data','frame_guard_actor','guard_phases_session','validate_guard_attack_phases'])
 run('phases-parse-'+script,['--headless','--check-only','--script',`res://scripts/tools/${script}.gd`],null,20000);
for(const render of process.argv.includes('--headless-only') ? [false] : [false,true]){
 for(const [scene,marker] of [['guard_attack_phases','ASHBOUND_GUARD_PHASES_OK groups=8'],['painted_combat','ASHBOUND_PAINTED_COMBAT_OK groups=8'],['combat_feedback','ASHBOUND_COMBAT_FEEDBACK_OK groups=9']])
  run(`phases-${scene}-${render?'render':'core'}`,[...(render?['--windowed','--resolution','1600x900','--position','-10000,-10000']:['--headless']),`res://scripts/tools/validate_${scene}.tscn`],marker);
}
console.log('ASHBOUND_GUARD_PHASES_CHECKS_OK');
