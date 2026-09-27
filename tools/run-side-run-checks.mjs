import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
const baseline=args.includes('--baseline-root')?args[args.indexOf('--baseline-root')+1]:root;
const stage=path.join(root,'.tools/export-staging/side-run-validation');
const godot=path.join(baseline,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const out=path.join(root,'.tools/forest-route-checks');
function run(id,options,marker){
 const log=path.join(out,id+'.log'),fd=fs.openSync(log,'w');let error;
 try{execFileSync(godot,['--path',stage,...options,'--','--no-mouse-capture'],{windowsHide:true,timeout:180000,stdio:['ignore',fd,fd]});}catch(e){error=e;}finally{fs.closeSync(fd);}
 const text=fs.readFileSync(log,'utf8');
 if(error||/SCRIPT ERROR:|^ERROR:|TIMEOUT|_FAIL/m.test(text)||!text.includes(marker)){console.log(text.slice(-5000));throw Error('Failed '+id);}
 console.log('PASS '+id+' '+marker);
}
const graphics=['--windowed','--resolution','1280x720','--position','-10000,-10000'];
run('side-run-render',[...graphics,'res://scripts/tools/validate_side_run.tscn'],'ASHBOUND_SIDE_RUN_OK groups=12');
fs.copyFileSync(path.join(process.env.APPDATA,'AshBound_Forest_Route_QA/side-run-results.json'),path.join(out,'side-run-pc.json'));
for(const [name,marker]of [
 ['courtyard_run','ASHBOUND_COURTYARD_RUN_OK'],['courtyard_run_touch','ASHBOUND_COURTYARD_RUN_TOUCH_OK'],
 ['character_visual','ASHBOUND_CHARACTER_VISUAL_OK'],['backpack_visual','ASHBOUND_BACKPACK_VISUAL_OK'],
 ['hero_projection','ASHBOUND_HERO_PROJECTION_OK cases=120 rendered=0']
])run('side-regression-'+name,['--headless','--fixed-fps','60','--script','res://scripts/tools/validate_'+name+'.gd'],marker);
run('side-projection-render',[...graphics,'--script','res://scripts/tools/validate_hero_projection.gd'],'ASHBOUND_HERO_PROJECTION_OK cases=120 rendered=10');
for(const [name,marker]of [['combat_dodge','ASHBOUND_COMBAT_DODGE_OK groups=10'],['combat_feedback','ASHBOUND_COMBAT_FEEDBACK_OK groups=9']])
 run('side-regression-'+name,['--headless','res://scripts/tools/validate_'+name+'.tscn'],marker);
run('side-forest-core',['--headless','--fixed-fps','60','res://scripts/tools/validate_forest_route.tscn'],'ASHBOUND_FOREST_ROUTE_OK groups=8');
console.log('ASHBOUND_SIDE_RUN_CHECKS_OK');
