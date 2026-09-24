// Build the preview stage first. Validate both the complete report and process log.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const args=process.argv.slice(2),arg=(k,d)=>args.includes(k)?args[args.indexOf(k)+1]:d;
const baseline=path.resolve(arg('--baseline-root',root));
const godot=process.env.ASHBOUND_GODOT||path.join(baseline,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const stage=path.join(root,'.tools/export-staging/village-walkthrough-preview');
const out=path.join(root,'.tools/village-doors-v2-checks');
fs.mkdirSync(out,{recursive:true});
for(const [name,options] of [
 ['pc-headless',['--headless','--fixed-fps','120']],
 ['pc-visual',['--resolution','1280x720','--position','6000,2000']],
 ['pc-4by3',['--resolution','1200x900','--position','6000,2000']]
]){
 const log=path.join(out,name+'.log'),dir=path.join(out,name),fd=fs.openSync(log,'w');let error;
 try{execFileSync(godot,['--path',stage,...options,'res://scripts/tools/validate_village_walkthrough.tscn','--','--no-mouse-capture','--output',dir],{cwd:root,windowsHide:true,timeout:300000,stdio:['ignore',fd,fd]});}catch(e){error=e;}finally{fs.closeSync(fd);}
 const text=fs.readFileSync(log,'utf8');
 if(error||/SCRIPT ERROR:|^ERROR:|VILLAGE_QA_FAIL/m.test(text)||!text.includes('VILLAGE_QA_COMPLETE failures=0 buildings=3'))throw Error(name+' failed; inspect '+log);
 const report=JSON.parse(fs.readFileSync(path.join(dir,'results.json'),'utf8'));
 if(report.version!=='0.22.1'||report.failures.length||report.completed.join(',')!=='H01,W01,B01'||report.checks<206)throw Error(name+' incomplete report');
 console.log('PASS '+name+' checks='+report.checks);
}
