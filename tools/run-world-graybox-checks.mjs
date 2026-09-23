// Run after build-world-graybox.mjs --stage-only. A success marker alone is insufficient.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const args=process.argv.slice(2),arg=(k,d)=>args.includes(k)?args[args.indexOf(k)+1]:d;
const baseline=path.resolve(arg('--baseline-root',root));
const godot=process.env.ASHBOUND_GODOT||path.join(baseline,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const stage=path.join(root,'.tools/export-staging/world-graybox-preview');
const out=path.join(root,'.tools/world-graybox-checks');
const routeCount=JSON.parse(fs.readFileSync(path.join(root,'assets/world/graybox-v1/layout.json'),'utf8')).roads.length*2;
fs.mkdirSync(out,{recursive:true});
for(const [name,options,userArgs,expected] of [
 ['pc-headless',['--headless','--fixed-fps','120'],[],routeCount],
 ['pc-visual',['--resolution','1280x720','--position','6000,2000'],['--screens-only'],0],
 ['pc-4by3',['--resolution','1200x900','--position','6000,2000'],['--screens-only'],0]
]){
 const log=path.join(out,name+'.log'),dir=path.join(out,name),fd=fs.openSync(log,'w');let error;
 try{execFileSync(godot,['--path',stage,...options,'res://scripts/tools/validate_world_graybox.tscn','--',...userArgs,'--no-mouse-capture','--output',dir],{cwd:root,windowsHide:true,timeout:900000,stdio:['ignore',fd,fd]});}catch(e){error=e;}finally{fs.closeSync(fd);}
 const text=fs.readFileSync(log,'utf8');
 if(error||/SCRIPT ERROR:|^ERROR:|WORLD_QA_FAIL/m.test(text)||!text.includes(`WORLD_GRAYBOX_QA_COMPLETE failures=0 routes=${expected}`))throw Error(name+' failed; inspect '+log);
 const report=JSON.parse(fs.readFileSync(path.join(dir,'results.json'),'utf8'));
 if(report.failures.length||report.routes.length!==expected||report.routes.some(r=>!r.passed))throw Error(name+' incomplete report');
 console.log('PASS '+name+' routes='+expected);
}
