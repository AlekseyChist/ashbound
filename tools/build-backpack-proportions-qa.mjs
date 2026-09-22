// Codex QA: run the same independent paired-art suite in an isolated Android app.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const stage = path.join(root, '.tools/export-staging/backpack-proportions-qa');
const output = path.join(root, '.tools/builds/android/ashbound-backpack-proportions-qa.apk');
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], {
  cwd: root, encoding: 'utf8', windowsHide: true,
}).trim().split(/\r?\n/);
for (const file of new Set(files)) {
  const source = path.join(root, file);
  if (!fs.existsSync(source) || !fs.statSync(source).isFile()) continue;
  const target = path.join(stage, file);
  fs.mkdirSync(path.dirname(target), {recursive: true});
  fs.copyFileSync(source, target);
}
const script = 'scripts/tools/backpack_android_validation.gd';
const scene = 'scripts/tools/backpack_android_validation.tscn';
const test = fs.readFileSync(path.join(root, 'scripts/tools/validate_painted_frames.gd'), 'utf8')
  .replace('extends SceneTree', 'extends Node\nvar root: Window')
  .replace('func _initialize() -> void:', 'func _ready() -> void:\n\troot = get_tree().root')
  .replaceAll('await process_frame', 'await get_tree().process_frame')
  .replaceAll('await physics_frame', 'await get_tree().physics_frame')
  .replaceAll('current_scene = scene', 'get_tree().current_scene = scene')
  .replaceAll('quit(', 'get_tree().quit(')
  .replaceAll('"res://.tools/', '"user://');
fs.writeFileSync(path.join(stage, script), test);
fs.writeFileSync(path.join(stage, scene), `[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://${script}" id="1"]\n\n[node name="BackpackValidation" type="Node"]\nscript = ExtResource("1")\n`);
const resources = [scene, 'scripts/courtyard/adaptive_screen_root.gd',
  'scripts/tools/fist_technique_sandbox.tscn', 'scripts/tools/fist_preview_toolbar.gd',
  ...['novice', 'novice_pack', 'trained', 'trained_pack'].map(id => `assets/characters/courtyard/fist-preview/${id}_frames.tres`)];
for (const file of ['project.godot', 'export_presets.cfg']) {
  const target = path.join(stage, file);
  let data = fs.readFileSync(target, 'utf8');
  if (file === 'project.godot') {
    data = data.replace(/run\/main_scene="[^"]+"/, `run/main_scene="res://${scene}"`)
      .replace('config/name="ASHBOUND"', 'config/name="ASHBOUND Backpack QA"')
      .replace('version_control/autoload_on_startup=true', 'version_control/autoload_on_startup=false');
  } else {
    data = data.replaceAll('export_files=PackedStringArray(', `export_files=PackedStringArray(${resources.map(f => `"res://${f}"`).join(', ')}, `)
      .replaceAll('org.ashbound.courtyard', 'org.ashbound.backpackqa')
      .replaceAll('package/name="AshBound Courtyard"', 'package/name="AshBound Backpack QA"');
  }
  fs.writeFileSync(target, data);
}
fs.mkdirSync(path.dirname(output), {recursive: true});
const godot = path.join(root, '.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
for (const [step, args] of [['import', ['--editor', '--import', '--quit']],
  ['android', ['--export-debug', 'Android Courtyard', output]]]) {
  const log = path.join(root, `.tools/backpack-proportions-qa-${step}.log`);
  const fd = fs.openSync(log, 'w');
  try {
    execFileSync(godot, ['--headless', '--path', stage, ...args], {
      cwd: root, windowsHide: true, timeout: 240000, stdio: ['ignore', fd, fd],
    });
  } finally { fs.closeSync(fd); }
  if (/SCRIPT ERROR:|^ERROR:/m.test(fs.readFileSync(log, 'utf8'))) throw Error(`Godot errors: ${log}`);
  console.log(`BACKPACK_PROPORTIONS_QA_${step.toUpperCase()}_OK`);
}
console.log(output);
