from PIL import Image,ImageDraw
im=Image.new('RGBA',(627,627),(245,241,233,255));d=ImageDraw.Draw(im)
d.line([(190,580),(415,580)],fill=(80,80,80),width=3)
d.ellipse((239,31,323,134),outline=(90,90,90),width=3)
d.line([(264,142),(260,210),(279,341)],fill=(110,110,110),width=18)
d.line([(284,344),(272,452),(266,550),(315,572)],fill=(70,100,200),width=35)
d.line([(263,344),(359,414),(306,498),(354,517)],fill=(210,80,70),width=38)
for xy in [(263,344),(359,414),(306,498)]:
 d.ellipse((xy[0]-8,xy[1]-8,xy[0]+8,xy[1]+8),fill=(245,210,200))
im.save('art/characters/sprite-gait-lab/passing-b-guide.png')
