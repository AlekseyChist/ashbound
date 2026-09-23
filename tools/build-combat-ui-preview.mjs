// Codex packaging/QA: isolated preview, never edits the source project or owner imports.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=path.resolve(import.meta.dirname,'..');
const args=process.argv.slice(2), validation=args.includes('--validate');
const opt=(key,def)=>args.includes(key)?args[args.indexOf(key)+1]:def;
const local=path.resolve(opt('--baseline-root',root));
const uiBook=args.includes('--ui-book');
const hudInput=args.includes('--hud-input')||uiBook;
const name=uiBook?(validation?'ui-book-validation':'ui-book-preview'):hudInput?(validation?'hud-input-validation':'hud-input-preview'):(validation?'combat-ui-validation':'combat-ui-preview');
const stage=path.join(root,'.tools/export-staging',name);
const sha=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const files=execFileSync('git',['ls-files','--cached','--others','--exclude-standard'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/);
const manifest={};
for(const f of new Set(files)){
 if(f.startsWith('docs/')||f.startsWith('tools/')||f.startsWith('.codex')||f.endsWith('.md'))continue;
 const src=path.join(root,f),dst=path.join(stage,f);
 if(!fs.existsSync(src)||!fs.statSync(src).isFile())continue;
 fs.mkdirSync(path.dirname(dst),{recursive:true});fs.copyFileSync(src,dst);manifest[f]=sha(src);
}
const checkpoint=JSON.parse(fs.readFileSync(path.join(local,'.tools/session-checkpoints/2026-09-22-end-of-day/checkpoint.json'),'utf8'));
for(const [f,h] of Object.entries(checkpoint.savedLocalFiles))if(f.endsWith('.import')){
 if(sha(path.join(local,f))!==h)throw Error('Owner import changed: '+f);
 fs.copyFileSync(path.join(local,f),path.join(stage,f));manifest[f]=h;
}
const cache=path.join(local,'.tools/export-staging/dodge-preview/.godot/imported');
if(fs.existsSync(cache)&&!fs.existsSync(path.join(stage,'.godot/imported')))fs.cpSync(cache,path.join(stage,'.godot/imported'),{recursive:true});
const scene=validation?(uiBook?'scripts/tools/validate_ui_book.tscn':hudInput?'scripts/tools/validate_hud_input.tscn':'scripts/tools/validate_combat_ui.tscn'):'scripts/tools/combat_dodge_sandbox.tscn';
const version=uiBook?'0.18.4-ui-book':hudInput?'0.18.3-hud-input':'0.18.2-combat-ui', code=uiBook?44:hudInput?43:42;
const packageId=validation?(uiBook?'org.ashbound.uibookvalidation':hudInput?'org.ashbound.hudinputvalidation':'org.ashbound.combatuivalidation'):'org.ashbound.fistqa';
// Keep the previous combat export scope; add only new UI and its QA.
const resources = [scene, "scripts/tools/validate_hud_input.gd", "scripts/tools/validate_combat_ui.tscn", "scripts/tools/combat_tools_toolbar.gd", "scripts/tools/validate_combat_ui.gd", 'scripts/tools/combat_dodge_sandbox.tscn', ...['player','session','toolbar','sandbox'].map(id=>'scripts/tools/combat_dodge_'+id+'.gd'), 'scripts/tools/guard_phases_sandbox.tscn', 'scripts/tools/guard_phases_sandbox.gd', 'scripts/tools/guard_phases_session.gd', 'scripts/tools/frame_guard_actor.gd', 'scripts/tools/attack_frame_data.gd', 'assets/combat/guard_unarmed_v1.tres', 'scripts/tools/painted_combat_sandbox.tscn', 'scripts/tools/painted_effect_pool.gd', ...['fx','trails','session','sandbox'].map(id=>'scripts/tools/painted_combat_'+id+'.gd'), ...['hit','block','perfect_block','windup','swing'].map(id=>'assets/vfx/painted-combat-v1/'+id+'.png'), 'scripts/tools/combat_feedback_sandbox.tscn', 'scripts/tools/combat_swing_trails.gd', 'scripts/tools/validate_combat_feedback.gd', ...['fx','player','session','sandbox'].map(id=>'scripts/tools/combat_feedback_'+id+'.gd'), 'scripts/tools/corner_enemy_sandbox.tscn', ...['actor','visual','session','level','toolbar','preview_toolbar'].map(id=>'scripts/tools/corner_enemy_'+id+'.gd'), ...['wolf','guard'].map(id=>'assets/characters/courtyard/enemy-preview/'+id+'_frames.tres'), 'scripts/tools/fist_defense_sandbox.tscn',
  'scripts/tools/fist_technique_sandbox.tscn',
  'scripts/tools/fist_defense_controller.gd','scripts/tools/fist_defense_player.gd',
  'scripts/tools/fist_defense_toolbar.gd','scripts/tools/fist_preview_toolbar.gd',
  'scripts/courtyard/adaptive_screen_root.gd',
  ...['novice','novice_pack','trained','trained_pack'].flatMap(id=>['fist-preview','fist-defense'].map(dir=>`assets/characters/courtyard/${dir}/${id}_frames.tres`))
].map(file=>`res://${file}`);
let project=fs.readFileSync(path.join(stage,'project.godot'),'utf8')
 .replace(/run\/main_scene="[^"]+"/,`run/main_scene="res://${scene}"`)
 .replace('config/name="ASHBOUND"',`config/name="ASHBOUND ${validation?'Combat UI Validation':'Combat Dodge'}"`)
 .replace(/config\/version="[^"]+"/,`config/version="${version}"`)
 .replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false');
if(validation)project=project.replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="AshBound_CONS_UI_QA"');
fs.writeFileSync(path.join(stage,'project.godot'),project);
let presets=fs.readFileSync(path.join(stage,'export_presets.cfg'),'utf8')
 .replaceAll('export_files=PackedStringArray(',`export_files=PackedStringArray(${resources.map(v=>JSON.stringify(v)).join(', ')}, `)
 .replaceAll('org.ashbound.courtyard',packageId)
 .replaceAll('package/name="AshBound Courtyard"',`package/name="AshBound ${validation?'Combat UI Validation':'Combat UI'}"`)
 .replace(/version\/code=\d+/,`version/code=${code}`)
 .replace(/version\/name="[^"]+"/,`version/name="${version}"`);
fs.writeFileSync(path.join(stage,'export_presets.cfg'),presets);
fs.mkdirSync(path.join(stage,'.tools'),{recursive:true});
fs.mkdirSync(path.join(root,'.tools/combat-ui-checks'),{recursive:true});
fs.writeFileSync(path.join(root,'.tools/combat-ui-checks',name+'-sources.json'),JSON.stringify(manifest,null,2));
const godot=process.env.ASHBOUND_GODOT||path.join(local,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
run('import',['--editor','--import','--quit']);
if(!args.includes('--stage-only')){
 const android=path.join(root,`.tools/builds/android/ashbound-${name}.apk`);
 const windows=path.join(root,`.tools/builds/${uiBook?'ui-book-preview':hudInput?'hud-input-preview':'combat-ui-preview'}/AshBound-Combat-UI.exe`);
 fs.mkdirSync(path.dirname(android),{recursive:true});fs.mkdirSync(path.dirname(windows),{recursive:true});
 run('android',['--export-debug','Android Courtyard',android]);
 if(!validation)run('windows',['--export-debug','Windows Courtyard',windows]);
 console.log(JSON.stringify({version,code,packageId,android,apkSHA256:sha(android),...(validation?{}:{windows,exeSHA256:sha(windows)})}));
}
function run(label,options){
 const log=path.join(root,`.tools/${name}-${label}.log`),fd=fs.openSync(log,'w');let fail;
 try{execFileSync(godot,['--headless','--path',stage,...options],{cwd:root,windowsHide:true,timeout:240000,stdio:['ignore',fd,fd]});}catch(e){fail=e;}finally{fs.closeSync(fd);}
 const output=fs.readFileSync(log,'utf8');
 if(fail||/SCRIPT ERROR:|^ERROR:/m.test(output)){console.log(JSON.stringify({status:fail?.status,signal:fail?.signal,code:fail?.code}));console.log(output.slice(-7000));throw Error('Packaging failed: '+label);}
 console.log('PASS '+name+' '+label);
}
