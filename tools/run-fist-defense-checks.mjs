// Independent Codex QA. Copy source into an isolated project; never import over owner files.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root = path.resolve(import.meta.dirname, '..');
const stage = path.join(root, '.tools/export-staging/defense-checks');
const godot = path.join(root, '.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], {cwd:root, encoding:'utf8', windowsHide:true}).trim().split(/\r?\n/);
for (const file of new Set(files)) {
  const source = path.join(root, file), dest = path.join(stage, file);
  if (!fs.existsSync(source) || !fs.statSync(source).isFile()) continue;
  fs.mkdirSync(path.dirname(dest), {recursive:true}); fs.copyFileSync(source, dest);
}
fs.mkdirSync(path.join(stage, '.tools'), {recursive:true});
const project = path.join(stage, 'project.godot');
fs.writeFileSync(project, fs.readFileSync(project,'utf8').replace('version_control/autoload_on_startup=true', 'version_control/autoload_on_startup=false'));
function run(name, args, marker) {
  const log = path.join(root, `.tools/defense-${name}.log`), fd = fs.openSync(log, 'w');
  let failed;
  try { execFileSync(godot, ['--path',stage,...args], {windowsHide:true,timeout:180000,stdio:['ignore',fd,fd]}); }
  catch(error) { failed = error; } finally { fs.closeSync(fd); }
  const output = fs.readFileSync(log,'utf8');
  if (failed || /SCRIPT ERROR:|^ERROR:/m.test(output) || (marker && !marker.test(output))) {
    const diagnostics = output.split(/\r?\n/).filter(line=>/ERROR|FAIL|INCOMPLETE| at:| at |GDScript/i.test(line));
    console.log(diagnostics.length ? diagnostics.join('\n').slice(-10000) : output.slice(-2000));
    throw Error(`Failed ${name}: ${log}`);
  }
  console.log(`PASS ${name}`);
}
run('import', ['--headless','--editor','--import','--quit']);
run('core', ['--headless','res://scripts/tools/validate_fist_defense.tscn'], /ASHBOUND_FIST_DEFENSE_OK groups=12/);
if (!process.argv.includes('--core-only')) {
  run('ui', ['--headless','res://scripts/tools/validate_fist_defense_ui.tscn'], /ASHBOUND_FIST_DEFENSE_UI_OK/);
  const regressions = process.argv.includes('--focused') ? [] : ['fist_sandbox','fist_techniques','attack_interruption','adaptive_display','localization','courtyard_localization','painted_frames','touch_inventory'];
  for (const name of regressions) {
    run(name, ['--headless','--script',`res://scripts/tools/validate_${name}.gd`], /^ASHBOUND_[A-Z_]+_OK/m);
  }
  for (const name of ['core','ui']) {
    run(`render-${name}`, ['--windowed','--position','-10000,-10000',`res://scripts/tools/validate_fist_defense${name==='ui'?'_ui':''}.tscn`], /^ASHBOUND_FIST_DEFENSE(_UI)?_OK/m);
  }
}
console.log('ASHBOUND_DEFENSE_CHECKS_OK');
