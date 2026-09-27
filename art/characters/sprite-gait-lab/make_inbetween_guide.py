from PIL import Image,ImageDraw
im=Image.new('RGB',(1254,1254),'#f4f1e9');d=ImageDraw.Draw(im)
near=[([(313,343),(349,452),(336,561),(385,580)],[(313,343),(276,443),(235,517),(273,537)]),
      ([(313,328),(280,435),(253,551),(300,580)],[(313,328),(378,408),(357,509),(403,532)])]
for i in range(4):
 ox=(i%2)*627;oy=(i//2)*627
 a,b=near[i%2]
 if i>=2:a,b=b,a
 def line(points,color,width):
  d.line([(x+ox,y+oy) for x,y in points],fill=color,width=width,joint='curve')
  for x,y in points:
   r=width/2;d.ellipse((x+ox-r,y+oy-r,x+ox+r,y+oy+r),fill=color)
 d.line((ox+130,oy+595,ox+470,oy+595),fill='#aaa699',width=2)
 d.ellipse((ox+263,oy+42,ox+348,oy+145),outline='#777777',width=3)
 line([(298,154),(309,240),(313,a[0][1])],'#888888',50)
 line(b,'#5071b5',28);line(a,'#c56051',30)
 arm_back=[(295,169),(274,254),(280,327)]
 arm_front=[(295,169),(333,250),(354,318)]
 na,fa=(arm_back,arm_front) if i in (0,3) else (arm_front,arm_back)
 line(fa,'#5071b5',16);line(na,'#c56051',18)
 d.text((ox+20,oy+20),str(i+1),fill='#777777')
im.save('art/characters/sprite-gait-lab/inbetween-guide.png')
