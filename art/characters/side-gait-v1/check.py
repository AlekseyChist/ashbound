"""Codex acceptance: pose outcomes, RGBA, paired bodies, deterministic/failing bakes."""
from pathlib import Path
import copy, hashlib, json, math, tempfile
import numpy as np
from PIL import Image, ImageDraw
import build

config=json.loads((build.HERE/'rig.json').read_text(encoding='utf8'))
out=build.ROOT/'.tools/side-gait-art'
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before={p.name:digest(p) for p in out.glob('*.png') if '-zoom' not in p.name}
build.build(config,out)
before={p.name:digest(p) for p in out.glob('*.png') if '-zoom' not in p.name}
build.build(config,out)
assert all(digest(out/n)==v for n,v in before.items()),'Non-deterministic bake'
poses=json.loads((out/'poses.json').read_text(encoding='utf8'))
checks=[]
for action in ['walk','run']:
    bare=Image.open(out/f'{action}-bare.png');packed=Image.open(out/f'{action}-pack.png')
    assert bare.mode==packed.mode=='RGBA' and bare.size==packed.size==(1536,768)
    signatures=set()
    for i in range(8):
        rect=((i%4)*384,(i//4)*384,(i%4+1)*384,(i//4+1)*384)
        b=np.array(bare.crop(rect));p=np.array(packed.crop(rect));a=b[:,:,3]
        assert not a[:4].any() and not a[-4:].any() and not a[:,:4].any() and not a[:,-4:].any(),'Clipped frame'
        assert (a>127).sum()>12000,'Missing body'
        assert np.array_equal(b[290:],p[290:]),'Backpack changed legs'
        pose=next(v for v in poses if v['action']==action and v['frame']==i)
        head_poly=([(148,4),(208,4),(208,50),(190,70),(173,67),(156,54),(147,40)] if action=='walk' else [(174,28),(245,28),(245,72),(223,90),(205,91),(198,76),(176,78)])
        anchor=config['actions'][action]['joints']['hip'];off=(192-anchor[0],pose['hip'][1]-anchor[1])
        head=Image.new('L',(384,384));ImageDraw.Draw(head).polygon([(x+off[0],y+off[1]) for x,y in head_poly],fill=255)
        head_mask=(np.array(head)>0)&(b[:,:,3]>250)
        assert head_mask.sum()>1500 and np.array_equal(b[head_mask],p[head_mask]),'Backpack changed visible head'
        n,f=pose['legs'][1],pose['legs'][0]
        assert n['phase']==i and f['phase']==(i+4)%8
        # Both contact poses must exchange the leading physical limb.
        if i in [0,4]:
            lead=n['ankle'][0]-f['ankle'][0]
            hands=pose['hands'][1]['xy'][0]-pose['hands'][0]['xy'][0]
            assert lead>70 if i==0 else lead< -70
            assert lead*hands<0,'Hands do not oppose leading leg'
        if action=='walk' or i in [0,1,4,5]:
            bottom=int(np.where(a>127)[0].max());assert abs(bottom-374)<=2,('No ground support',action,i,bottom)
        if action=='run' and i in [3,7]:
            assert int(np.where(a>127)[0].max())<360,'No flight phase'
        signatures.add(hashlib.sha256(b.tobytes()).hexdigest())
    assert len(signatures)==8,'Repeated pose pixels'
    checks.append(action+': alpha, eight distinct poses, alternating contacts, counter-swing, support, identical head/legs in pair')

# Bad art data must reject without replacing an existing export.
for label,mutate in [
    ('source',lambda c:c['source_sha256'].update({next(iter(c['source_sha256'])):'0'*64})),
    ('phase-count',lambda c:c['actions']['run']['arm_angles'].pop()),
    ('baseline',lambda c:c['actions']['walk'].update(sole_y=[1]*8)),
    ('reach',lambda c:c['actions']['run']['ankles'][0].__setitem__(0,500)),
]:
    bad=copy.deepcopy(config);mutate(bad)
    snapshot={p.name:digest(p) for p in out.glob('*.png')}
    try:build.build(bad,out)
    except ValueError:pass
    else:raise AssertionError('Accepted bad '+label)
    assert snapshot=={p.name:digest(p) for p in out.glob('*.png')},'Damaged last good bake'
    checks.append('reject '+label+' without changing prior exports')
result={'checks':checks,'source_hashes':'PASS','determinism':'PASS','poses':32,'visual_review':'separate from programmatic checks'}
(out/'art-checks.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
print('ASHBOUND_SIDE_GAIT_ART_OK poses=32 failures=0 rejected=4')
