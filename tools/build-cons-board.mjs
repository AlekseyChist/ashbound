// Codex QA artifact assembly: copy untouched captures and write traceable metadata.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
const root=path.resolve(import.meta.dirname,'..');
const source=path.join(root,'.tools/cons-stage/.tools/cons-captures');
// D-080: the board and its captures stay local, never in Git.
const out=path.join(root,'local/exports/cons-01');
const args=process.argv.slice(2);
const local=args.includes('--baseline-root')?path.resolve(args[args.indexOf('--baseline-root')+1]):root;
const sha=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const manifest=JSON.parse(fs.readFileSync(path.join(source,'manifest.json'),'utf8'));
const motion=JSON.parse(fs.readFileSync(path.join(source,'motion.json'),'utf8'));
if(manifest.errors.length||manifest.captures.length!==171||motion.errors.length||motion.captures.length!==1200)throw Error('Incomplete capture');
const ids=manifest.captures.map(c=>c.id);
if(new Set(ids).size!==171)throw Error('Duplicate captures');
const expected=[];
for(const t of ['novice','trained'])for(const p of ['bare','pack'])for(const v of ['back','front','left','right'])for(const a of ['idle','windup','contact','guard','hit','dodge'])expected.push(`hero-${t}-${p}-${v}-${a}`);
for(const k of ['guard','wolf'])for(const v of ['back','front','left','right'])for(const a of ['idle','walk','windup','attack','hit'])expected.push(`enemy-${k}-${v}-${a}`);
for(const k of ['guard','wolf'])for(const a of ['windup','cue','hit','block','perfect_block','hero_hit'])for(const angle of ['','-oblique'])expected.push(`combat-${k}-${a}${angle}`);
for(const l of ['ru','en'])for(const a of ['normal','pressed','disabled','cue'])expected.push(`ui-${l}-${a}`);
expected.push('courtyard-gameplay','courtyard-world','courtyard-overview');
if(expected.some(id=>!ids.includes(id)))throw Error('Missing matrix cell');
for(let n=0;n<1200;n++)if(motion.captures[n].id!==`motion-${String(n).padStart(4,'0')}`||motion.captures[n].step!==n%120)throw Error('Incomplete motion sequence');
fs.mkdirSync(path.join(out,'images'),{recursive:true});
for(const c of manifest.captures){
 if(c.width!==1280||c.height!==720)throw Error('Unexpected dimensions: '+c.id);
 fs.copyFileSync(path.join(source,c.file),path.join(out,'images',c.file));
 c.sha256=sha(path.join(out,'images',c.file));
 c.file='images/'+c.file;
}
const phoneFiles=['s23-ready.png','s23-real-held.png','s23-real-swing.png','s23-real-menu.png'];
for(const file of phoneFiles){
 const original=path.join(local,'.tools/combat-dodge-checks',file);
 fs.copyFileSync(original,path.join(out,'images',file));
 const png=fs.readFileSync(original);
 if(png.readUInt32BE(16)!==2340||png.readUInt32BE(20)!==1080)throw Error('Unexpected phone dimensions');
 manifest.captures.push({id:file.slice(0,-4),file:'images/'+file,width:2340,height:1080,category:'phone',platform:'Samsung S23 / Android 16',version:'0.18.1-combat-dodge / code 41',date:'2026-09-22',language:'ru',mode:'archived device screenshot from COMBAT_DODGE_CHECKS; not a new device run',sha256:sha(original)});
}
const old=JSON.parse(fs.readFileSync(path.join(local,'.tools/combat-dodge-checks/source-manifest.json'),'utf8'));
let matched=0;
for(const [file,hash] of Object.entries(old)){
 if(file.endsWith('.md'))continue;
 const current=path.join(root,'.tools/cons-stage',file);
 if(!fs.existsSync(current)||sha(current)!==hash)throw Error('Game baseline differs: '+file);
 matched++;
}
const provenance={baseCommit:'9d3a9487ade6d45091ffc88111601227bb7869f2',gameplayCommit:'1187be2a2cde7b3f5b44608a57429671a7d58777',version:'0.18.1-combat-dodge',scene:'scripts/tools/combat_dodge_sandbox.tscn',created:'2026-09-22',gameFilesMatchedToShippedPreview:matched,renderer:'Godot 4.7.2 / Vulkan Forward Mobile / RTX 4090 Laptop',captureSize:[1280,720],phone:'S23 screenshots reused with original hashes; OnePlus not tested',stills:171,motionFrames:1200,motionFPS:60,motionSeconds:20,framePolicy:'Pinned native frames for comparison; deterministic actual simulation for contact and motion. Encounter + home relocated together only inside QA. No pixel retouch.',videoSHA256:sha(path.join(out,'combat-motion.mp4')),captureScriptSHA256:sha(path.join(root,'scripts/tools/capture_cons_baseline.gd'))};
const data={provenance,captures:manifest.captures};
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(data,null,2));
fs.writeFileSync(path.join(out,'data.js'),'window.CONS_DATA = '+JSON.stringify(data)+';\n');
fs.writeFileSync(path.join(out,'motion-events.json'),JSON.stringify(motion.captures.filter(c=>c.step===119),null,2));
fs.mkdirSync(path.join(out,'evidence'),{recursive:true});
for(const name of ['stills','motion','parse']){
 const log=fs.readFileSync(path.join(root,'.tools/cons-'+name+'.log'),'utf8').replaceAll('\r\n','\n').trimEnd()+'\n';
 fs.writeFileSync(path.join(out,'evidence',name+'.log'),log);
}
console.log(JSON.stringify({result:'PASS',captures:manifest.captures.length,gameFilesMatched:matched,videoBytes:fs.statSync(path.join(out,'combat-motion.mp4')).size}));
