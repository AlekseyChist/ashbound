// Codex independent QA, always in a disposable project.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const stage=path.join(root,'.tools/export-staging/corner-enemy-checks');
const godot=process.env.ASHBOUND_GODOT||path.join(root,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
if(process.env.ASHBOUND_QA_CACHE&&!fs.existsSync(path.join(stage,'.godot/imported')))
 fs.cpSync(process.env.ASHBOUND_QA_CACHE,path.join(stage,'.godot/imported'),{recursive:true});
for(const file of new Set(execFileSync('git',['ls-files','--cached','--others','--exclude-standard'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/))){
 const src=path.join(root,file),dest=path.join(stage,file);
 if(!fs.existsSync(src)||!fs.statSync(src).isFile())continue;
 fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(src,dest);
}
const project=path.join(stage,'project.godot');
fs.writeFileSync(project,fs.readFileSync(project,'utf8').replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false'));
fs.mkdirSync(path.join(stage,'.tools'),{recursive:true});
function run(name,args,marker){
 const log=path.join(root,`.tools/enemy-${name}.log`),fd=fs.openSync(log,'w');let failed;
 try{execFileSync(godot,['--path',stage,...args],{windowsHide:true,timeout:150000,stdio:['ignore',fd,fd]});}catch(e){failed=e;}finally{fs.closeSync(fd);}
 const out=fs.readFileSync(log,'utf8');
 if(failed||/SCRIPT ERROR:|^ERROR:/m.test(out)||(marker&&!marker.test(out))){
  console.log(out.slice(-10000));throw Error(log);
 }
 console.log('PASS '+name);
}
run('import',['--headless','--editor','--import','--quit']);
if(process.argv.includes('--import-only'))process.exit(0);
run('core',['--headless','res://scripts/tools/validate_corner_enemies.tscn'],/ASHBOUND_CORNER_ENEMIES_OK groups=12/);
if(!process.argv.includes('--core-only')){
 for(const [scene,marker]of [['validate_block_timing_cue',/ASHBOUND_BLOCK_CUE_OK groups=7/],['validate_fist_defense',/ASHBOUND_FIST_DEFENSE_OK groups=12/],['validate_fist_defense_ui',/ASHBOUND_FIST_DEFENSE_UI_OK groups=6/],['validate_fist_defense_poses',/ASHBOUND_FIST_DEFENSE_POSES_OK groups=6/]])
  run(scene,['--headless',`res://scripts/tools/${scene}.tscn`],marker);
 for(const name of ['fist_sandbox','fist_techniques','attack_interruption','adaptive_display','localization','courtyard_localization','painted_frames','touch_inventory'])
  run(name,['--headless','--script',`res://scripts/tools/validate_${name}.gd`],/^ASHBOUND_[A-Z_]+_OK/m);
}
if(!process.argv.includes('--headless-only'))run('render',['--windowed','--resolution','1600x900','--position','-10000,-10000','res://scripts/tools/validate_corner_enemies.tscn'],/ASHBOUND_CORNER_ENEMIES_OK groups=12/);
console.log('ASHBOUND_CORNER_ENEMY_CHECKS_OK');
