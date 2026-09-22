// Codex QA runner. No game source changes; build a disposable, isolated capture project.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=path.resolve(import.meta.dirname,'..');
const args=process.argv.slice(2);
const option=(key,fallback)=>args.includes(key)?args[args.indexOf(key)+1]:fallback;
const local=path.resolve(option('--baseline-root',root));
const stage=path.join(root,'.tools/cons-stage');
const godot=process.env.ASHBOUND_GODOT||path.join(local,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const cache=option('--cache',path.join(local,'.tools/export-staging/dodge-preview/.godot/imported'));
const motion=args.includes('--motion');
const sha=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
fs.mkdirSync(stage,{recursive:true});
if(!args.includes('--skip-import')){
 const files=execFileSync('git',['ls-files','--cached','--others','--exclude-standard'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/);
 const sources={};
 for(const f of files){
  if(f.startsWith('docs/')||f.startsWith('.codex')||f.startsWith('tools/')||f.endsWith('.md'))continue;
  const src=path.join(root,f);if(!fs.statSync(src).isFile())continue;
  const dest=path.join(stage,f);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(src,dest);sources[f]=sha(src);
 }
 // Preserve locally used import settings without staging the owner's unrelated changes.
 const checkpoint=path.join(local,'.tools/session-checkpoints/2026-09-22-end-of-day/checkpoint.json');
 if(fs.existsSync(checkpoint))for(const [f,h] of Object.entries(JSON.parse(fs.readFileSync(checkpoint,'utf8')).savedLocalFiles)){
  if(!f.endsWith('.import'))continue;
  if(sha(path.join(local,f))!==h)throw Error('Owner baseline changed: '+f);
  fs.copyFileSync(path.join(local,f),path.join(stage,f));sources[f]=h;
 }
 if(fs.existsSync(cache)&&!fs.existsSync(path.join(stage,'.godot/imported')))fs.cpSync(cache,path.join(stage,'.godot/imported'),{recursive:true});
 const project=path.join(stage,'project.godot');
 let s=fs.readFileSync(project,'utf8').replace('config/name="ASHBOUND"','config/name="ASHBOUND CONS QA"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="AshBound_CONS_QA"').replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false').replace('window/size/mode=2','window/size/mode=0');
 fs.writeFileSync(project,s);
 fs.mkdirSync(path.join(stage,'.tools/cons-captures'),{recursive:true});
 fs.writeFileSync(path.join(stage,'.tools/cons-captures/sources.json'),JSON.stringify({baseCommit:execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8',windowsHide:true}).trim(),version:'0.18.1-combat-dodge',scene:'scripts/tools/combat_dodge_sandbox.tscn',captureScene:'scripts/tools/capture_cons_baseline.tscn',sources},null,2));
 run('import',['--headless','--editor','--import','--quit'],null,180000);
}
if(!args.includes('--import-only')){
 for(const ext of ['gd','tscn'])fs.copyFileSync(path.join(root,'scripts/tools/capture_cons_baseline.'+ext),path.join(stage,'scripts/tools/capture_cons_baseline.'+ext));
 const sourceFile=path.join(stage,'.tools/cons-captures/sources.json');
 const sourceData=JSON.parse(fs.readFileSync(sourceFile,'utf8'));
 for(const ext of ['gd','tscn']){const f='scripts/tools/capture_cons_baseline.'+ext;sourceData.sources[f]=sha(path.join(stage,f));}
 fs.writeFileSync(sourceFile,JSON.stringify(sourceData,null,2));
 run('parse',['--headless','--check-only','--script','res://scripts/tools/capture_cons_baseline.gd'],null,20000);
 run(motion?'motion':'stills',['--windowed','--resolution','1280x720','--position','-10000,-10000',...(motion?['--fixed-fps','60']:[]),'res://scripts/tools/capture_cons_baseline.tscn',...(motion?['--','--motion']:[])],motion?'captures=1200 motion=true':'captures=171 motion=false',300000);
}
function run(label,options,marker,timeout){
 const log=path.join(root,'.tools/cons-'+label+'.log');const fd=fs.openSync(log,'w');let fail;
 try{execFileSync(godot,['--path',stage,...options],{cwd:stage,windowsHide:true,timeout,stdio:['ignore',fd,fd]});}catch(e){fail=e;}finally{fs.closeSync(fd);}
 const out=fs.readFileSync(log,'utf8');
 if(fail||/SCRIPT ERROR:|^ERROR:|FEEDBACK_FAIL:|CONS_CAPTURE_FAILED|CONS_CAPTURE_TIMEOUT/m.test(out)||(marker&&!out.includes(marker))){console.log(out.slice(-16000));throw Error('Capture failed: '+label);}
 console.log('PASS '+label+' '+log);
}
