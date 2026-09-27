"""Exercise the local-model builder's rejection paths in isolated stage fixtures."""
from pathlib import Path
import subprocess,sys,hashlib,json

stage=Path(sys.argv[1]).resolve()
godot=Path(sys.argv[2]).resolve()
out=stage/'.tools/painted-builder-qa'
out.mkdir(parents=True,exist_ok=True)
script=(stage/'scripts/tools/build_painted_motion_frames.gd').read_text(encoding='utf-8')
source=(stage/'assets/characters/courtyard/traveler_frames.tres').read_bytes()
fixture=out/'frames.tres'
runner=out/'builder.gd'

def call(path):
    relative=path.relative_to(stage).as_posix()
    return subprocess.run([str(godot),'--headless','--path',str(stage),'--script','res://'+relative],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=45)

prep=out/'prepare.gd'
prep.write_text('extends SceneTree\nfunc _initialize():\n\tvar image = Image.create(2, 2, false, Image.FORMAT_RGBA8)\n\timage.fill(Color.WHITE)\n\tvar texture = ImageTexture.create_from_image(image)\n\tvar err = ResourceSaver.save(texture, "res://.tools/painted-builder-qa/wrong-size.tres")\n\tquit(0 if err == OK else 1)\n',encoding='utf-8')
result=call(prep)
assert result.returncode==0 and 'SCRIPT ERROR' not in result.stdout+result.stderr,result.stdout+result.stderr
rows=[]
for case in ['missing-texture','wrong-size','missing-clip','invalid-scale']:
    resource=source.decode('utf-8')
    code=script.replace('res://assets/characters/courtyard/traveler_frames.tres','res://.tools/painted-builder-qa/frames.tres')
    if case=='missing-texture':
        code=code.replace('res://assets/characters/courtyard/painted-motion-v2/walk.png','res://.tools/painted-builder-qa/absent.png')
    elif case=='wrong-size':
        code=code.replace('res://assets/characters/courtyard/painted-motion-v2/walk.png','res://.tools/painted-builder-qa/wrong-size.tres')
    elif case=='missing-clip':
        resource=resource.replace('"name": &"walk_side"','"name": &"missing_side"')
    elif case=='invalid-scale':
        import re
        resource=re.sub(r'metadata/pixel_size_side = [^\n]+','metadata/pixel_size_side = -1.0',resource)
    fixture.write_text(resource,encoding='utf-8')
    runner.write_text(code,encoding='utf-8')
    before=fixture.read_bytes()
    result=call(runner)
    log=result.stdout+result.stderr
    (out/(case+'.log')).write_text(log,encoding='utf-8')
    assert result.returncode==1 and 'ASHBOUND_PAINTED_MOTION_BUILD_OK' not in log,(case,result.returncode,log)
    assert 'SCRIPT ERROR' not in log,(case,log)
    assert fixture.read_bytes()==before,(case,'modified resource on failure')
    assert (stage/'assets/characters/courtyard/traveler_frames.tres').read_bytes()==source
    rows.append({'case':case,'exit':result.returncode,'resource_unchanged':True})
(out/'results.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
print('ASHBOUND_PAINTED_BUILDER_REJECTIONS_OK cases=4 no resource writes')
