// Codex packaging: isolated PC/Android comparison scene, or Android core QA.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const validate = process.argv.includes('--validate');
const name = validate ? 'fist-validation' : 'fist-preview';
const stage = path.join(root, '.tools/export-staging', name);
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], {
  cwd: root, encoding: 'utf8', windowsHide: true,
}).trim().split(/\r?\n/);
for (const file of new Set(files)) {
  const source = path.join(root, file);
  if (!fs.existsSync(source) || !fs.statSync(source).isFile()) continue;
  const dest = path.join(stage, file);
  fs.mkdirSync(path.dirname(dest), {recursive: true});
  fs.copyFileSync(source, dest);
}
let scene = 'scripts/tools/fist_technique_sandbox.tscn';
if (validate) {
  const script = 'scripts/tools/fist_android_validation.gd';
  scene = 'scripts/tools/fist_android_validation.tscn';
  const test = fs.readFileSync(path.join(root, 'scripts/tools/validate_fist_techniques.gd'), 'utf8')
    .replace('extends SceneTree', 'extends Node\nvar root: Window')
    .replace('func _initialize() -> void:', 'func _ready() -> void:\n\troot = get_tree().root')
    .replaceAll('await process_frame', 'await get_tree().process_frame')
    .replaceAll('quit(', 'get_tree().quit(');
  fs.writeFileSync(path.join(stage, script), test);
  fs.writeFileSync(path.join(stage, scene), `[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://${script}" id="1"]\n\n[node name="FistValidation" type="Node"]\nscript = ExtResource("1")\n`);
}
const resources = ['novice', 'novice_pack', 'trained', 'trained_pack']
  .map(id => `res://assets/characters/courtyard/fist-preview/${id}_frames.tres`);
// Selected-resource exports do not collect this script created inside _ready.
if (!validate) resources.push('res://scripts/tools/fist_preview_toolbar.gd');
for (const file of ['project.godot', 'export_presets.cfg']) {
  const dest = path.join(stage, file);
  let data = fs.readFileSync(dest, 'utf8');
  if (file === 'project.godot') {
    data = data.replace(/run\/main_scene="[^"]+"/, `run/main_scene="res://${scene}"`)
      .replace('config/name="ASHBOUND"', `config/name="ASHBOUND ${validate ? 'Fist Validation' : 'Fist Preview'}"`)
      .replace('version_control/autoload_on_startup=true', 'version_control/autoload_on_startup=false');
  } else {
    const extra = [scene.replace(/^/, 'res://'), ...resources].map(v => `"${v}"`).join(', ');
    data = data.replaceAll('export_files=PackedStringArray(', `export_files=PackedStringArray(${extra}, `)
      .replaceAll('org.ashbound.courtyard', validate ? 'org.ashbound.fistvalidation' : 'org.ashbound.fistqa')
      .replaceAll('package/name="AshBound Courtyard"', `package/name="AshBound ${validate ? 'Fist Validation' : 'Fist Preview'}"`);
  }
  fs.writeFileSync(dest, data);
}
const godot = path.join(root, '.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const android = path.join(root, `.tools/builds/android/ashbound-${name}.apk`);
const windows = path.join(root, '.tools/builds/fist-preview/AshBound-Fist-Preview.exe');
fs.mkdirSync(path.dirname(android), {recursive: true});
fs.mkdirSync(path.dirname(windows), {recursive: true});
const steps = [['import', ['--editor', '--import', '--quit']],
  ['android', ['--export-debug', 'Android Courtyard', android]]];
if (!validate) steps.push(['windows', ['--export-debug', 'Windows Courtyard', windows]]);
for (const [step, args] of steps) {
  const log = path.join(root, `.tools/${name}-${step}.log`);
  const fd = fs.openSync(log, 'w');
  try {
    execFileSync(godot, ['--headless', '--path', stage, ...args], {
      cwd: root, windowsHide: true, timeout: 240000, stdio: ['ignore', fd, fd],
    });
  } finally { fs.closeSync(fd); }
  if (/SCRIPT ERROR:|^ERROR:/m.test(fs.readFileSync(log, 'utf8'))) throw Error(`Godot errors: ${log}`);
  console.log(`${name.toUpperCase()}_${step.toUpperCase()}_OK`);
}
if (!validate) {
  const log = path.join(root, '.tools/fist-preview-package-smoke.log');
  execFileSync(windows, ['--headless', '--quit-after', '120', '--log-file', log], {
    cwd: root, windowsHide: true, timeout: 45000, stdio: 'ignore',
  });
  const output = fs.readFileSync(log, 'utf8');
  if (/SCRIPT ERROR:|^ERROR:/m.test(output) || !output.includes('ASHBOUND_FIST_SANDBOX_READY')) {
    throw Error(`Packaged preview smoke failed: ${log}`);
  }
  console.log('FIST_PREVIEW_PACKAGE_SMOKE_OK');
}
console.log(android);
if (!validate) console.log(windows);
