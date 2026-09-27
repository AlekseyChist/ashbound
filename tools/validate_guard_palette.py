"""Independent Codex oracle and failure checks for the offline guard correction."""
from pathlib import Path
import os, json, hashlib, copy, shutil, subprocess, re
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / '.tools/guard-palette-qa'
GODOT = os.environ.get('ASHBOUND_GODOT', str(ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'))
RECIPE = 'art/characters/fist-defense-palette-v1/palette.json'
SCRIPT = 'scripts/tools/correct_trained_guard_palette.gd'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
STAGE.mkdir(parents=True, exist_ok=True)
(STAGE / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Palette QA"\n', encoding='utf8')
recipe = json.loads((ROOT / RECIPE).read_text(encoding='utf8'))
for rel in [RECIPE, SCRIPT, recipe['base'], recipe['paint']]:
    dest=STAGE / rel; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(ROOT / rel,dest)
originals={k:digest(STAGE / recipe[k]) for k in ['base','paint']}
out=STAGE / '.tools/guard-palette/export'
logs=STAGE / '.tools/logs'; logs.mkdir(parents=True,exist_ok=True)

def run(label, args=None, ok=True):
    p=subprocess.run([GODOT,'--headless','--path',str(STAGE),'--script','res://'+SCRIPT,'--',*(args or [])],capture_output=True,timeout=90)
    text=(p.stdout+p.stderr).decode('utf8',errors='replace')
    (logs / (label+'.log')).write_text(text,encoding='utf8')
    assert not re.search(r'SCRIPT ERROR:|^ERROR:',text,re.M),(label,text)
    assert (p.returncode==0)==ok,(label,p.returncode,text)
    assert ('ASHBOUND_GUARD_PALETTE_OK sheets=2' if ok else 'ASHBOUND_GUARD_PALETTE_FAIL') in text,(label,text)
    if not ok: assert 'ASHBOUND_GUARD_PALETTE_OK' not in text
    print('PASS',label,flush=True)

def tone(a):
    b=a.copy(); rgb=a[:627,:,:3].astype(np.float64)
    lum=rgb @ np.array([.2126,.7152,.0722])
    ratio=np.power(np.maximum(lum/255,1e-20),recipe['gamma']-1)
    changed=np.floor(rgb*ratio[:,:,None]+.5).clip(0,255).astype(np.uint8)
    mask=(a[:627,:,3]>0)&(lum>0)
    b[:627,:,:3][mask]=changed[mask]
    return b

run('valid')
base=np.array(Image.open(STAGE / recipe['base']))
paint=np.array(Image.open(STAGE / recipe['paint']))
old_pack=base.copy(); expected_pack=tone(base); corrected_paint=tone(paint)
for x,y,w,h in recipe['regions']:
    old_pack[y:y+h,x:x+w]=paint[y:y+h,x:x+w]
    expected_pack[y:y+h,x:x+w]=corrected_paint[y:y+h,x:x+w]
actuals={}
for name,old,expected in [('trained',base,tone(base)),('trained-pack',old_pack,expected_pack)]:
    a=np.array(Image.open(out / (name+'.png'))); actuals[name]=a
    assert a.shape==old.shape and np.array_equal(a[:,:,3],old[:,:,3]),'alpha/geometry changed'
    assert np.array_equal(a[627:],old[627:]),'hit reaction changed'
    assert np.array_equal(a[old[:,:,3]==0],old[old[:,:,3]==0]),'hidden RGB changed'
    assert np.max(np.abs(a.astype(int)-expected.astype(int)))<=1,'tone curve/original hue not preserved'
    opaque=(old[:627,:,3]>250)
    old_lum=old[:627,:,:3]@np.array([.2126,.7152,.0722])
    new_lum=a[:627,:,:3]@np.array([.2126,.7152,.0722])
    assert (new_lum[opaque]<=old_lum[opaque]+.6).all(),'unexpected brightening'
    assert not np.any(opaque&(old_lum>8)&(new_lum<2)),'opaque detail crushed to black'
mask=np.ones(base.shape[:2],bool)
for x,y,w,h in recipe['regions']: mask[y:y+h,x:x+w]=False
assert np.array_equal(actuals['trained'][mask],actuals['trained-pack'][mask]),'equipment widened/repainted body'
stable={p.name:digest(p) for p in out.glob('*.png')}
run('repeat')
assert stable=={p.name:digest(p) for p in out.glob('*.png')},'not deterministic'
before={p.name:(digest(p),p.stat().st_mtime_ns) for p in out.glob('*')}
bad={}
def case(name,fn):
    d=copy.deepcopy(recipe); fn(d); bad[name]=d
case('hash',lambda d:d.update(base_sha256='0'*64))
case('gamma-string',lambda d:d.update(gamma='1.16'))
case('gamma-small',lambda d:d.update(gamma=.5))
case('gamma-large',lambda d:d.update(gamma=9))
case('gamma-bool',lambda d:d.update(gamma=True))
case('schema',lambda d:d.update(schema=99))
case('width',lambda d:d.update(width=1253))
case('row',lambda d:d.update(guard_rows=628))
case('empty-regions',lambda d:d.update(regions=[]))
case('fractional-region',lambda d:d['regions'][0].__setitem__(0,1.5))
case('outside-region',lambda d:d['regions'][0].__setitem__(2,9000))
case('traversal',lambda d:d.update(base='../outside.png'))
case('missing',lambda d:d.update(paint='art/missing.png'))
case('empty-base',lambda d:d.update(base=''))
case('empty-hash',lambda d:d.update(base_sha256=''))
for kind,mode,size in [('bad-size','RGBA',(32,32)),('bad-format','RGB',(1254,1254))]:
    rel='.tools/'+kind+'.png'; Image.new(mode,size).save(STAGE/rel)
    case(kind,lambda d,rel=rel:d.update(base=rel,base_sha256=digest(STAGE/rel)))
for name,data in bad.items():
    rel='.tools/bad-'+name+'.json'; (STAGE / rel).write_text(json.dumps(data),encoding='utf8')
    run(name,['--manifest=res://'+rel],False)
    assert before=={p.name:(digest(p),p.stat().st_mtime_ns) for p in out.glob('*')},'failed preflight overwrote output'
for name,args in [('unknown',['--oops']),('outside-output',['--out-dir=res://assets/']),('traversal-output',['--out-dir=res://.tools/../assets/'])]:
    run(name,args,False)
    assert before=={p.name:(digest(p),p.stat().st_mtime_ns) for p in out.glob('*')}
assert originals=={k:digest(STAGE / recipe[k]) for k in ['base','paint']},'source mutation'
report={'gamma':recipe['gamma'],'outputs':stable,'failure_cases':len(bad)+3,'alpha':'exact','hit_row':'exact','outside_equipment_regions':'exact'}
(ROOT / '.tools/guard-palette-report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('ASHBOUND_GUARD_PALETTE_QA_OK outputs=2 failure_cases=20')
