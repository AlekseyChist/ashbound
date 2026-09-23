// Separate prototype package; never changes the source project's launch scene.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=path.resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
const opt=(key,fallback)=>args.includes(key)?args[args.indexOf(key)+1]:fallback;
const baseline=path.resolve(opt('--baseline-root',root));
const qa=args.includes('--validate'),name=qa?'world-graybox-validation':'world-graybox-preview';
const stage=path.join(root,'.tools/export-staging',!qa&&args.includes('--release-stage')?'world-graybox-release':name),out=path.join(root,'.tools/world-graybox-checks');
const sha=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const files=execFileSync('git',['ls-files','--cached','--others','--exclude-standard'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/);
const manifest={};fs.mkdirSync(out,{recursive:true});
for(const f of new Set(files)){
 if(/^(docs|tools|art|\.codex)/.test(f)||f.endsWith('.md'))continue;
 const src=path.join(root,f),dst=path.join(stage,f);
 if(!fs.existsSync(src)||!fs.statSync(src).isFile())continue;
 fs.mkdirSync(path.dirname(dst),{recursive:true});fs.copyFileSync(src,dst);manifest[f]=sha(src);
}
const checkpointPath=path.join(baseline,'.tools/session-checkpoints/2026-09-22-end-of-day/checkpoint.json');
if(fs.existsSync(checkpointPath)){
 const checkpoint=JSON.parse(fs.readFileSync(checkpointPath,'utf8').replace(/^\uFEFF/,''));
 for(const[f,h]of Object.entries(checkpoint.savedLocalFiles))if(f.endsWith('.import')){
  if(sha(path.join(baseline,f))!==h)throw Error('Owner import changed '+f);
  fs.copyFileSync(path.join(baseline,f),path.join(stage,f));manifest[f]=h;
 }
}
const cache=path.join(root,'.tools/export-staging/walk-phone-preview/.godot/imported');
if(fs.existsSync(cache)&&!fs.existsSync(path.join(stage,'.godot/imported')))fs.cpSync(cache,path.join(stage,'.godot/imported'),{recursive:true});
const version='0.21.0-world-graybox',code=50;
const title=`AshBound World Graybox${qa?' QA':''}`;
const scene=qa?'scripts/tools/validate_world_graybox.tscn':'scenes/world/world_graybox.tscn';
const packageId=qa?'org.ashbound.worldgrayboxvalidation':'org.ashbound.worldgraybox';
let project=fs.readFileSync(path.join(stage,'project.godot'),'utf8')
 .replace(/run\/main_scene="[^"]+"/,`run/main_scene="res://${scene}"`)
 .replace('config/name="ASHBOUND"',`config/name="${title}"`)
 .replace(/config\/version="[^"]+"/,`config/version="${version}"`)
 .replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false')
 .replace('window/size/mode=2','window/size/mode=0')
 .replace('[application]',`[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="AshBound_World_Graybox${qa?'_QA':''}"`);
fs.writeFileSync(path.join(stage,'project.godot'),project);
const resources=[scene,'scenes/world/world_graybox.tscn',...files.filter(f=>f.startsWith('scripts/world/world_graybox')||f.startsWith('assets/world/graybox-v1/')||f.startsWith('assets/characters/world-graybox-v1/')).filter(f=>!f.endsWith('.import')&&!f.endsWith('.uid'))];
let presets=fs.readFileSync(path.join(stage,'export_presets.cfg'),'utf8')
 .replaceAll('export_files=PackedStringArray(',`export_files=PackedStringArray(${resources.map(v=>JSON.stringify('res://'+v)).join(', ')}, `)
 .replace(/include_filter="([^"]*)"/g,(_,filter)=>`include_filter="${filter?filter+',':''}assets/world/graybox-v1/*.bin,assets/world/graybox-v1/*.json"`)
 .replaceAll('org.ashbound.courtyard',packageId)
 .replaceAll('package/name="AshBound Courtyard"',`package/name="${title}"`)
 .replace(/version\/code=\d+/,`version/code=${code}`)
 .replace(/version\/name="[^"]+"/,`version/name="${version}"`);
fs.writeFileSync(path.join(stage,'export_presets.cfg'),presets);
fs.writeFileSync(path.join(out,name+'-sources.json'),JSON.stringify(manifest,null,2));
const godot=process.env.ASHBOUND_GODOT||path.join(baseline,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
run('import',['--editor','--import','--quit']);
if(!args.includes('--stage-only')){
 const android=path.join(root,`.tools/builds/android/ashbound-${name}.apk`);
 const windows=path.join(root,'.tools/builds/world-graybox/AshBound-World-Graybox.exe');
 fs.mkdirSync(path.dirname(android),{recursive:true});fs.mkdirSync(path.dirname(windows),{recursive:true});
 run('android',['--export-debug','Android Courtyard',android]);
 if(!qa)run('windows',['--export-debug','Windows Courtyard',windows]);
 const result={version,code,packageId,android,apkSHA256:sha(android),...(!qa?{windows,exeSHA256:sha(windows)}:{})};
 fs.writeFileSync(path.join(out,name+'-artifacts.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}
function run(label,options){
 const log=path.join(out,name+'-'+label+'.log'),fd=fs.openSync(log,'w');let error;
 try{execFileSync(godot,['--headless','--path',stage,...options],{cwd:root,windowsHide:true,timeout:300000,stdio:['ignore',fd,fd]});}catch(e){error=e;}finally{fs.closeSync(fd);}
 const text=fs.readFileSync(log,'utf8');
 if(error||/SCRIPT ERROR:|^ERROR:/m.test(text)){console.log(text.slice(-6500));throw Error('Build failed '+label+' '+(error?.status??''));}
 console.log('PASS '+name+' '+label);
}
