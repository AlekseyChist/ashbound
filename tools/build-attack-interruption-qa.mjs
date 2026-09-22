// Codex QA packaging: run the independent suite and a real Home/return probe
// in a separate Android package without touching the owner's game profile.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const stage = path.join(root, '.tools/export-staging/attack-interruption-qa');
const output = path.join(root, '.tools/builds/android/ashbound-attack-qa.apk');
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], {
  cwd: root, encoding: 'utf8', windowsHide: true,
}).trim().split(/\r?\n/);
for (const file of new Set(files)) {
  const source = path.join(root, file);
  if (!fs.existsSync(source) || !fs.statSync(source).isFile()) continue;
  const dest = path.join(stage, file);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(source, dest);
}

let test = fs.readFileSync(path.join(root, 'scripts/tools/validate_attack_interruption.gd'), 'utf8')
  .replace('extends SceneTree', 'extends Node\nvar root: Window')
  .replace('func _initialize() -> void:', 'func _ready() -> void:\n\troot = get_tree().root\n\tprocess_mode = Node.PROCESS_MODE_ALWAYS')
  .replaceAll('await process_frame', 'await get_tree().process_frame')
  .replaceAll('await physics_frame', 'await get_tree().physics_frame')
  .replaceAll('paused = ', 'get_tree().paused = ')
  .replaceAll('quit(', 'get_tree().quit(')
  .replace('root.size = Vector2i(1920, 1080)', 'if OS.get_name() != "Android":\n\t\troot.size = Vector2i(1920, 1080)')
  .replace('get_tree().quit(0)', '_begin_real_lifecycle.call_deferred()');
test += `
# QA-only slow windup gives adb time to send an actual Android Home event.
var _lifecycle_armed := false
var _lifecycle_left := false
var _lifecycle_returning := false

func _begin_real_lifecycle() -> void:
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await get_tree().process_frame
	player = level.get_node("Actors/Player")
	player.strike_requested.connect(func(): strikes += 1)
	reset_attack()
	Engine.time_scale = 0.01
	player.request_attack()
	check(player.is_attacking(), "real lifecycle windup started")
	_lifecycle_armed = true
	print("ATTACK_LIFECYCLE_ARMED")
	await get_tree().create_timer(60.0, true, false, true).timeout
	printerr("ATTACK_INTERRUPTION_TIMEOUT: Home/return probe not completed")
	get_tree().quit(1)

func _notification(what: int) -> void:
	if not _lifecycle_armed:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_lifecycle_left = true
		print("ATTACK_LIFECYCLE_LEFT strikes=%d" % strikes)
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _lifecycle_left and not _lifecycle_returning:
		_lifecycle_returning = true
		_after_real_return.call_deferred()

func _after_real_return() -> void:
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.8).timeout
	check(strikes == 0 and not player.is_attacking(), "actual Android return has no delayed hit")
	player.request_attack()
	await get_tree().create_timer(0.2).timeout
	check(strikes == 1, "fresh actual Android attack after return")
	_lifecycle_armed = false
	if errors.is_empty():
		print("ASHBOUND_ATTACK_ANDROID_LIFECYCLE_OK groups=10")
		get_tree().quit(0)
	else:
		printerr("ATTACK_INTERRUPTION_FAILED: actual Android lifecycle")
		get_tree().quit(1)
`;
const script = 'scripts/tools/attack_android_validation.gd';
const scene = 'scripts/tools/attack_android_validation.tscn';
fs.writeFileSync(path.join(stage, script), test);
fs.writeFileSync(path.join(stage, scene), `[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://${script}" id="1"]\n\n[node name="AttackValidation" type="Node"]\nscript = ExtResource("1")\n`);
for (const file of ['project.godot', 'export_presets.cfg']) {
  const dest = path.join(stage, file);
  let text = fs.readFileSync(dest, 'utf8');
  if (file === 'project.godot') {
    text = text.replace(/run\/main_scene="[^"]+"/, `run/main_scene="res://${scene}"`)
      .replace('version_control/autoload_on_startup=true', 'version_control/autoload_on_startup=false');
  } else {
    text = text.replaceAll('export_files=PackedStringArray(', `export_files=PackedStringArray("res://${scene}", `)
      .replaceAll('org.ashbound.courtyard', 'org.ashbound.attackqa')
      .replaceAll('package/name="AshBound Courtyard"', 'package/name="AshBound Attack QA"');
  }
  fs.writeFileSync(dest, text);
}
fs.mkdirSync(path.dirname(output), { recursive: true });
const godot = path.join(root, '.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
for (const [name, args] of [
  ['import', ['--editor', '--import', '--quit']],
  ['export', ['--export-debug', 'Android Courtyard', output]],
]) {
  const log = path.join(root, `.tools/attack-qa-${name}.log`);
  const fd = fs.openSync(log, 'w');
  try {
    execFileSync(godot, ['--headless', '--path', stage, ...args], {
      cwd: root, windowsHide: true, timeout: 180000, stdio: ['ignore', fd, fd],
    });
  } finally {
    fs.closeSync(fd);
  }
  if (/SCRIPT ERROR:|^ERROR:/m.test(fs.readFileSync(log, 'utf8'))) throw Error(`Godot errors: ${log}`);
  console.log(`ATTACK_QA_${name.toUpperCase()}_OK`);
}
console.log(output);
