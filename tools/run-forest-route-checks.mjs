import fs from'node:fs';import path from'node:path';import{execFileSync}from'node:child_process';
const root=path.resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
const opt=(key,fallback)=>args.includes(key)?args[args.indexOf(key)+1]:fallback;
const baseline=path.resolve(opt('--baseline-root',root));
const qa=args.includes('--validation-stage'),stage=path.join(root,'.tools/export-staging',qa?'forest-route-validation':'forest-route-preview');
const rendered=args.includes('--render'),out=path.join(root,'.tools/forest-route-checks');fs.mkdirSync(out,{recursive:true});
const godot=process.env.ASHBOUND_GODOT||path.join(baseline,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const log=path.join(out,'route-'+(rendered?'render':'core')+'.log'),fd=fs.openSync(log,'w');let error;
try{execFileSync(godot,['--path',stage,...(rendered?['--windowed','--resolution','1280x720','--position','-10000,-10000']:['--headless']),...(args.includes('--realtime')?[]:['--fixed-fps','60']),'res://scripts/tools/validate_forest_route.tscn','--','--no-mouse-capture'],{cwd:root,windowsHide:true,timeout:750000,stdio:['ignore',fd,fd]});}catch(e){error=e;}finally{fs.closeSync(fd);}
const content=fs.readFileSync(log,'utf8');
if(error||/SCRIPT ERROR:|ERROR:|FOREST_FAIL|TIMEOUT/.test(content)||!content.includes('ASHBOUND_FOREST_ROUTE_OK groups=8')){console.log(content.slice(-8500));throw Error('Forest route QA failed '+(error?.status??''));}
const user=path.join(process.env.APPDATA,'AshBound_Forest_Route'+(qa?'_QA':''));
for(const f of fs.readdirSync(user).filter(f=>/^forest-.*\.(png|json)$/.test(f)))fs.copyFileSync(path.join(user,f),path.join(out,(rendered?'pc-render-':'pc-core-')+f));
console.log('PASS forest route 8 groups '+(rendered?'render':'core'));console.log(content.split(/\r?\n/).filter(s=>s.startsWith('FOREST_JOURNEY')).join('\n'));
