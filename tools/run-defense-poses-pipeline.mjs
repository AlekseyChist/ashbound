// Codex: import and validate native base/equipment composition in a disposable project.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const stage=path.join(root,'.tools/export-staging/defense-poses');
const cache=path.join(root,'.tools/export-staging/defense-checks/.godot/imported');
if(!fs.existsSync(path.join(stage,'.godot/imported'))&&fs.existsSync(cache))fs.cpSync(cache,path.join(stage,'.godot/imported'),{recursive:true});
for(const file of new Set(execFileSync('git',['ls-files','--cached','--others','--exclude-standard'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/))) {
 const src=path.join(root,file),dest=path.join(stage,file);
 if(!fs.existsSync(src)||!fs.statSync(src).isFile())continue;
 fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(src,dest);
}
const project=path.join(stage,'project.godot');
fs.writeFileSync(project,fs.readFileSync(project,'utf8').replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false'));
fs.mkdirSync(path.join(stage,'.tools'),{recursive:true});
const godot=path.join(root,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const log=path.join(root,'.tools/defense-poses-import.log');
const fd=fs.openSync(log,'w');
try{execFileSync(godot,['--headless','--path',stage,'--editor','--import','--quit'],{cwd:root,windowsHide:true,timeout:180000,stdio:['ignore',fd,fd]});}finally{fs.closeSync(fd);}
if(/SCRIPT ERROR:|^ERROR:/m.test(fs.readFileSync(log,'utf8')))throw Error(log);
const python=process.env.ASHBOUND_QA_PYTHON||'python';
execFileSync(python,[path.join(root,'tools/validate_fist_defense_pipeline.py'),...process.argv.slice(2)],{cwd:root,windowsHide:true,timeout:240000,stdio:'inherit'});
