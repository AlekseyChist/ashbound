// Codex packaging: isolated combat feedback preview or native independent QA.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root = path.resolve(import.meta.dirname, '..');
const validation = process.argv.includes('--validate');



const name = validation ? 'painted-validation' : 'painted-preview';
const stage = path.join(root, '.tools/export-staging', name);
const imported = path.join(root,'.tools/export-staging/corner-enemy-checks/.godot/imported');
if (fs.existsSync(imported)) fs.cpSync(imported,path.join(stage,'.godot/imported'),{recursive:true});
const files = execFileSync('git',['ls-files','--cached','--others','--exclude-standard'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/);
for (const file of new Set(files)) {
  const source = path.join(root,file), dest = path.join(stage,file);
  if (!fs.existsSync(source) || !fs.statSync(source).isFile()) continue;
  fs.mkdirSync(path.dirname(dest),{recursive:true}); fs.copyFileSync(source,dest);
}
const scene = validation ? 'scripts/tools/validate_painted_combat.tscn' : 'scripts/tools/painted_combat_sandbox.tscn';
const resources = [scene, 'scripts/tools/painted_combat_sandbox.tscn', 'scripts/combat/painted_effect_pool.gd', ...['fx','trails','session','sandbox'].map(id=>(fs.existsSync(path.join(root,'scripts/combat/painted_combat_'+id+'.gd'))?'scripts/combat/':'scripts/tools/')+'painted_combat_'+id+'.gd'), ...['hit','block','perfect_block','windup','swing'].map(id=>'assets/vfx/painted-combat-v1/'+id+'.png'), 'scripts/tools/combat_feedback_sandbox.tscn', 'scripts/combat/combat_swing_trails.gd', 'scripts/tools/validate_combat_feedback.gd', ...['fx','player','session','sandbox'].map(id=>(fs.existsSync(path.join(root,'scripts/combat/combat_feedback_'+id+'.gd'))?'scripts/combat/':'scripts/tools/')+'combat_feedback_'+id+'.gd'), 'scripts/tools/corner_enemy_sandbox.tscn', ...['actor','visual','session','level','toolbar','preview_toolbar'].map(id=>(fs.existsSync(path.join(root,'scripts/combat/corner_enemy_'+id+'.gd'))?'scripts/combat/':'scripts/tools/')+'corner_enemy_'+id+'.gd'), ...['wolf','guard'].map(id=>'assets/characters/courtyard/enemy-preview/'+id+'_frames.tres'), 'scripts/tools/fist_defense_sandbox.tscn',
  'scripts/tools/fist_technique_sandbox.tscn',
  'scripts/combat/fist_defense_controller.gd','scripts/combat/fist_defense_player.gd',
  'scripts/combat/fist_defense_toolbar.gd','scripts/tools/fist_preview_toolbar.gd',
  'scripts/courtyard/adaptive_screen_root.gd',
  ...['novice','novice_pack','trained','trained_pack'].flatMap(id=>['fist-preview','fist-defense'].map(dir=>`assets/characters/courtyard/${dir}/${id}_frames.tres`))
].map(file=>`res://${file}`);
const title = validation ? 'Painted Validation' : 'Painted Combat';
const version = '0.17.3-painted-combat';
const packageId = validation ? 'org.ashbound.paintedvalidation' : 'org.ashbound.fistqa';
for (const file of ['project.godot','export_presets.cfg']) {
  const target = path.join(stage,file);
  let data = fs.readFileSync(target,'utf8');
  if (file === 'project.godot') {
    data = data.replace(/run\/main_scene="[^"]+"/,`run/main_scene="res://${scene}"`)
      .replace('config/name="ASHBOUND"',`config/name="ASHBOUND ${title}"`)
      .replace(/config\/version="[^"]+"/,`config/version="${version}"`)
      .replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false');
  } else {
    const extra = resources.map(value=>`"${value}"`).join(', ');
    data = data.replaceAll('export_files=PackedStringArray(',`export_files=PackedStringArray(${extra}, `)
      .replaceAll('org.ashbound.courtyard',packageId)
      .replaceAll('package/name="AshBound Courtyard"',`package/name="AshBound ${title}"`)
      .replace(/version\/code=\d+/, 'version/code=38')
      .replace(/version\/name="[^"]+"/, `version/name="${version}"`);
  }
  fs.writeFileSync(target,data);
}
const godot = process.env.ASHBOUND_GODOT || path.join(root,'.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const android = path.join(root,`.tools/builds/android/ashbound-${name}.apk`);
const windows = path.join(root,'.tools/builds/painted-preview/AshBound-Painted-Combat.exe');
fs.mkdirSync(path.join(stage,'.tools'),{recursive:true});
fs.mkdirSync(path.dirname(android),{recursive:true});
fs.mkdirSync(path.dirname(windows),{recursive:true});
const steps = [['import',['--editor','--import','--quit']],['android',['--export-debug','Android Courtyard',android]]];
if (!validation) steps.push(['windows',['--export-debug','Windows Courtyard',windows]]);
for (const [step,args] of steps) {
  const log = path.join(root,`.tools/${name}-${step}.log`), fd = fs.openSync(log,'w');
  try {execFileSync(godot,['--headless','--path',stage,...args],{cwd:root,windowsHide:true,timeout:240000,stdio:['ignore',fd,fd]});}
  finally {fs.closeSync(fd);}
  if (/SCRIPT ERROR:|^ERROR:/m.test(fs.readFileSync(log,'utf8'))) throw Error(log);
  console.log(`PASS ${name} ${step}`);
}
if (!validation) {
  const log = path.join(root,'.tools/painted-preview-package-smoke.log');
  execFileSync(windows,['--headless','--quit-after','120','--log-file',log],{cwd:root,windowsHide:true,timeout:45000,stdio:'ignore'});
  const output = fs.readFileSync(log,'utf8');
  if (/SCRIPT ERROR:|^ERROR:/m.test(output) || !output.includes('ASHBOUND_PAINTED_COMBAT_READY')) throw Error(log);
  console.log('ASHBOUND_PAINTED_PACKAGE_SMOKE_OK');
}
console.log(android);
if (!validation) console.log(windows);
