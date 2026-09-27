"""An original vector-like pose diagram; does not read or alter any character image."""
from PIL import Image, ImageDraw
from pathlib import Path

out=Path(__file__).parent
im=Image.new('RGB',(1280,800),'#eeeeea'); d=ImageDraw.Draw(im)
# Screen coordinates in a 320x400 cell. Red is the near pair; blue is far.
# Near arm is opposite the near thigh. Second half exchanges the two pairs.
legs=[([(160,225),(211,288),(243,360)],[(160,225),(117,285),(72,343)]),
      ([(160,235),(177,298),(157,360)],[(160,235),(139,287),(103,312)]),
      ([(160,221),(139,290),(114,355)],[(160,221),(211,254),(178,311)]),
      ([(160,210),(115,275),(70,318)],[(160,210),(220,263),(238,340)])]
arms=[([(174,113),(122,165),(140,188)],[(174,113),(216,160),(246,135)]),
      ([(170,121),(150,172),(178,190)],[(170,121),(198,171),(229,155)]),
      ([(174,109),(207,157),(241,132)],[(174,109),(125,161),(143,184)]),
      ([(176,100),(217,147),(248,119)],[(176,100),(123,152),(141,177)])]
for i in range(8):
    ox=(i%4)*320; oy=(i//4)*400
    nl,fl=legs[i%4]; na,fa=arms[i%4]
    if i>=4:nl,fl,na,fa=fl,nl,fa,na
    def points(p):return [(x+ox,y+oy) for x,y in p]
    def limb(p,c,w):
        d.line(points(p),fill=c,width=w,joint='curve')
        for x,y in points(p):d.ellipse((x-w/2,y-w/2,x+w/2,y+w/2),fill=c)
    d.line((ox+10,oy+370,ox+310,oy+370),fill='#b0b0b0',width=2)
    limb(fl,'#326c9e',18); limb(fa,'#326c9e',16)
    limb([na[0],nl[0]],'#766c59',40)
    hx,hy=na[0][0]+6,na[0][1]-43
    d.ellipse((ox+hx-22,oy+hy-29,ox+hx+22,oy+hy+23),fill='#766c59')
    d.polygon(points([(hx+16,hy-7),(hx+35,hy+3),(hx+18,hy+8)]),fill='#766c59')
    limb(nl,'#bc4944',19);limb(na,'#bc4944',17)
    for p,c in [(nl,'#bc4944'),(fl,'#326c9e')]:
        x,y=p[-1];limb([(x-8,y),(x+24,y)],c,12)
    d.text((ox+10,oy+8),str(i)+'  RED=NEAR / BLUE=FAR',fill='#111111')
im.save(out/'run-pose-guide.png')
