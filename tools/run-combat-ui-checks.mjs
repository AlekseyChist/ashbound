// Codex independent acceptance. Build staging first with build-combat-ui-preview.mjs --validate --stage-only.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
const opt=(key,def)=>args.includes(key)?args[args.indexOf(key)+1]:def;
const local=path.resolve(opt('--baseline-root',root));
const hudInput=args.includes('--hud-input');
const stage=path.join(root,'.tools/export-staging',hudInput?'hud-input-validation':'combat-ui-validation');
const godot=process.env.ASHBOUND_GODOT||path.join(local,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const out=path.join(root,hudInput?'.tools/hud-input-checks':'.tools/combat-ui-checks');fs.mkdirSync(out,{recursive:true});
if(!fs.existsSync(path.join(stage,'project.godot')))throw Error('Build validation staging first');
for(const f of [...(hudInput?['validate_hud_input.gd','validate_hud_input.tscn']:[]),'combat_tools_toolbar.gd','combat_dodge_toolbar.gd','combat_dodge_sandbox.gd','validate_combat_ui.gd','validate_combat_ui.tscn'])fs.copyFileSync(path.join(root,'scripts/tools',f),path.join(stage,'scripts/tools',f));
if(hudInput)fs.copyFileSync(path.join(root,'scripts/courtyard/courtyard_hud.gd'),path.join(stage,'scripts/courtyard/courtyard_hud.gd'));
// Load through a scene so project autoload names resolve exactly as in the game.
fs.writeFileSync(path.join(stage,'.tools/preflight.gd'),'extends Node\nfunc _ready():\n\tfor file in ["combat_tools_toolbar.gd","combat_dodge_toolbar.gd","combat_dodge_sandbox.gd","validate_combat_ui.gd"]:\n\t\tvar script = load("res://scripts/tools/"+file)\n\t\tif script == null or not script.can_instantiate():\n\t\t\tprinterr("COMBAT_UI_INCOMPLETE parse ",file)\n\t\t\tget_tree().quit(1)\n\t\t\treturn\n\tprint("COMBAT_UI_PARSE_OK")\n\tget_tree().quit(0)\n');
fs.writeFileSync(path.join(stage,'.tools/preflight.tscn'),'[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://.tools/preflight.gd" id="1"]\n[node name="Preflight" type="Node"]\nscript=ExtResource("1")\n');
const parseFD=fs.openSync(path.join(out,'parse.log'),'w');let parseFailure;
try{execFileSync(godot,['--headless','--path',stage,'res://.tools/preflight.tscn'],{windowsHide:true,timeout:20000,stdio:['ignore',parseFD,parseFD]});}catch(e){parseFailure=e;}finally{fs.closeSync(parseFD);}
const parse=fs.readFileSync(path.join(out,'parse.log'),'utf8');
if(parseFailure||/ERROR:|INCOMPLETE/.test(parse)||!parse.includes('COMBAT_UI_PARSE_OK')){console.log(parse);throw Error('Preflight failed');}
console.log('PASS parse');
const suites=[...(hudInput?[['hud_input',9,'HUD_INPUT']]:[]),['combat_ui',12,'COMBAT_UI'],...(args.includes('--regressions')?[['combat_dodge',10,'COMBAT_DODGE'],['guard_attack_phases',8,'GUARD_PHASES'],['painted_combat',8,'PAINTED_COMBAT'],['combat_feedback',9,'COMBAT_FEEDBACK']]:[])];
for(const [scene,count,marker] of suites){
 const rendered=args.includes('--render');
 const log=path.join(out,`${scene}-${rendered?'render':'core'}.log`),fd=fs.openSync(log,'w');let failure;
 try{execFileSync(godot,['--path',stage,...(rendered?['--windowed','--resolution','1280x720','--position','-10000,-10000']:['--headless']),`res://scripts/tools/validate_${scene}.tscn`],{windowsHide:true,timeout:120000,stdio:['ignore',fd,fd]});}catch(e){failure=e;}finally{fs.closeSync(fd);}
 const content=fs.readFileSync(log,'utf8');
 if(failure||/SCRIPT ERROR:|ERROR:|FEEDBACK_FAIL:|INCOMPLETE|TIMEOUT/.test(content)||!content.includes(`ASHBOUND_${marker}_OK groups=${count}`)){console.log(content.slice(-10000));throw Error('Failed '+scene);}
 console.log(`PASS ${scene} ${count} groups ${rendered?'render':'core'}`);
}
if(hudInput && args.includes('--regressions') && !args.includes('--render')){
 for(const [name,marker,extra] of [
  ['courtyard_run_touch','ASHBOUND_COURTYARD_RUN_TOUCH_OK',[]],
  ['courtyard_run_touch','ASHBOUND_COURTYARD_RUN_TOUCH_OK',['--','--locale=en']],
  ['courtyard_restart_dialogue','ASHBOUND_COURTYARD_RESTART_DIALOGUE_OK groups=2',[]],
  ['touch_inventory','ASHBOUND_TOUCH_INVENTORY_OK',[]],
  ['attack_interruption','ASHBOUND_ATTACK_INTERRUPTION_OK groups=10',[]]
 ]){
  const log=path.join(out,name+(extra.length?'-en':'')+'.log'),fd=fs.openSync(log,'w');let failure;
  try{execFileSync(godot,['--headless','--path',stage,'--script',`res://scripts/tools/validate_${name}.gd`,...extra],{windowsHide:true,timeout:65000,stdio:['ignore',fd,fd]});}catch(e){failure=e;}finally{fs.closeSync(fd);}
  const content=fs.readFileSync(log,'utf8');
  if(failure||/SCRIPT ERROR:|ERROR:|_FAIL|INCOMPLETE|TIMEOUT/.test(content)||!content.includes(marker)){console.log(content.slice(-7000));throw Error('Failed '+name);}
  console.log(`PASS ${name}${extra.length?' EN':''}`);
 }
}
