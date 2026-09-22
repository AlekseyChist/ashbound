// Independent Codex tests in an isolated project, never import owner files.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const stage=path.join(root,'.tools/export-staging/block-cue-checks');
const godot=process.env.ASHBOUND_GODOT||path.join(root,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const cache=process.env.ASHBOUND_QA_CACHE;
if(cache&&!fs.existsSync(path.join(stage,'.godot/imported')))fs.cpSync(cache,path.join(stage,'.godot/imported'),{recursive:true});
const files=execFileSync('git',['ls-files','--cached','--others','--exclude-standard'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/);
for(const file of new Set(files)){
 const src=path.join(root,file),dest=path.join(stage,file);
 if(!fs.existsSync(src)||!fs.statSync(src).isFile())continue;
 fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(src,dest);
}
const project=path.join(stage,'project.godot');
fs.writeFileSync(project,fs.readFileSync(project,'utf8').replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false'));
fs.mkdirSync(path.join(stage,'.tools'),{recursive:true});
function run(name,args,marker){
 const log=path.join(root,`.tools/block-cue-${name}.log`),fd=fs.openSync(log,'w');
 let failed;
 try{execFileSync(godot,['--path',stage,...args],{windowsHide:true,timeout:120000,stdio:['ignore',fd,fd]});}catch(e){failed=e;}finally{fs.closeSync(fd);}
 const out=fs.readFileSync(log,'utf8');
 if(failed||/SCRIPT ERROR:|^ERROR:/m.test(out)||(marker&&!marker.test(out))){
  console.log(out.split(/\r?\n/).filter(x=>/ERROR|FAIL|INCOMPLETE|at:|GDScript/i.test(x)).join('\n').slice(-9000));
  throw Error(log);
 }
 console.log('PASS '+name);
}
run('import',['--headless','--editor','--import','--quit']);
run('cue',['--headless','res://scripts/tools/validate_block_timing_cue.tscn'],/ASHBOUND_BLOCK_CUE_OK groups=7/);
if(!process.argv.includes('--cue-only')){
 for(const [name,scene,marker]of [
  ['core','validate_fist_defense.tscn',/ASHBOUND_FIST_DEFENSE_OK groups=12/],
  ['ui','validate_fist_defense_ui.tscn',/ASHBOUND_FIST_DEFENSE_UI_OK groups=6/],
 ])run(name,['--headless','res://scripts/tools/'+scene],marker);
 for(const name of ['fist_sandbox','fist_techniques','attack_interruption','adaptive_display','localization','courtyard_localization','painted_frames','touch_inventory'])
  run(name,['--headless','--script',`res://scripts/tools/validate_${name}.gd`],/^ASHBOUND_[A-Z_]+_OK/m);
 if(fs.existsSync(path.join(root,'scripts/tools/validate_fist_defense_poses.tscn')))
  run('poses',['--headless','res://scripts/tools/validate_fist_defense_poses.tscn'],/ASHBOUND_FIST_DEFENSE_POSES_OK groups=6/);
}
if(!process.argv.includes('--headless-only')){
 run('render',['--windowed','--position','-10000,-10000','res://scripts/tools/validate_block_timing_cue.tscn'],/ASHBOUND_BLOCK_CUE_OK groups=7/);
 if(!process.argv.includes('--cue-only'))run('render-ui',['--windowed','--position','-10000,-10000','res://scripts/tools/validate_fist_defense_ui.tscn'],/ASHBOUND_FIST_DEFENSE_UI_OK groups=6/);
}
console.log('ASHBOUND_BLOCK_CUE_CHECKS_OK');
