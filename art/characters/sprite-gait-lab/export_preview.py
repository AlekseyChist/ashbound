from PIL import Image,ImageDraw
from pathlib import Path
p=Path('.tools/sprite-gait-lab')
sheet=Image.new('RGB',(1040,800),'#535b59')
d=ImageDraw.Draw(sheet)
frames=[]
for i in range(8):
 im=Image.open(p/('frame-%d.png'%i)).convert('RGB')
 frames.append(im)
 sheet.paste(im.crop((350,10,610,390)),(260*(i%4),400*(i//4)+20))
 d.text((260*(i%4)+10,400*(i//4)+5),str(i+1),fill='#eee6d6')
sheet.save('art/characters/sprite-gait-lab/eight-phases.jpg',quality=92)
frames[0].save('art/characters/sprite-gait-lab/walk-candidate.gif',save_all=True,append_images=frames[1:],duration=125,loop=0)
print('8-phase contact sheet and loop saved')
