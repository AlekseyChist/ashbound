import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
const baseline=args.includes('--baseline-root')?args[args.indexOf('--baseline-root')+1]:root;
const stage=path.join(root,'.tools/export-staging/painted-motion-validation');
const godot=path.join(baseline,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const out=path.join(root,'.tools/painted-motion-checks');fs.mkdirSync(out,{recursive:true});
function run(id,options,marker){
 const log=path.join(out,id+'.log'),fd=fs.openSync(log,'w');let error;
 try{execFileSync(godot,['--path',stage,...options,'--','--no-mouse-capture'],{windowsHide:true,timeout:180000,stdio:['ignore',fd,fd]});}catch(e){error=e;}finally{fs.closeSync(fd);}
 const text=fs.readFileSync(log,'utf8');
 if(error||/SCRIPT ERROR:|^ERROR:|TIMEOUT|_FAIL/m.test(text)||!text.includes(marker))throw Error(id+' failed: '+text.slice(-4500));
 console.log('PASS '+id+' '+marker);
}
const graphics=['--windowed','--resolution','1280x720','--position','-10000,-10000'];
run('gait-render',[...graphics,'res://scripts/tools/validate_painted_motion.tscn'],'ASHBOUND_PAINTED_MOTION_OK groups=16');
const user=path.join(process.env.APPDATA,'AshBound_Forest_Route_QA');
for(const f of fs.readdirSync(user))if(f==='painted-motion-results.json'||/^painted-.*\.png$/.test(f))fs.copyFileSync(path.join(user,f),path.join(out,f));
run('interpolation-render',[...graphics,'res://scripts/tools/validate_side_run.tscn'],'ASHBOUND_SIDE_RUN_OK groups=12');
fs.copyFileSync(path.join(user,'side-run-results.json'),path.join(out,'interpolation-results.json'));
for(const [name,marker]of [
 ['courtyard_run','ASHBOUND_COURTYARD_RUN_OK'],['courtyard_run_touch','ASHBOUND_COURTYARD_RUN_TOUCH_OK'],
 ['character_visual','ASHBOUND_CHARACTER_VISUAL_OK'],['backpack_visual','ASHBOUND_BACKPACK_VISUAL_OK'],
 ['hero_projection','ASHBOUND_HERO_PROJECTION_OK cases=120 rendered=0']
])run(name,['--headless','--fixed-fps','60','--script','res://scripts/tools/validate_'+name+'.gd'],marker);
run('forest-route',['--headless','--fixed-fps','60','res://scripts/tools/validate_forest_route.tscn'],'ASHBOUND_FOREST_ROUTE_OK groups=8');
console.log('ASHBOUND_PAINTED_MOTION_CHECKS_OK');
