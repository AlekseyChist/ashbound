"""Document-only measured elevations and habitation diagram; no 3D or image edits."""
from pathlib import Path
import json
import math
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Polygon
from matplotlib.font_manager import FontProperties

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
D=json.loads((HERE/"h01-spec.json").read_text(encoding="utf-8"))
FONT=FontProperties(fname=str(ROOT/"assets/ui/fonts/OpenSans-SemiBold.ttf"))
PAPER="#f3efe3"; INK="#263a34"; WOOD="#8d755b"; PLASTER="#d2c7af"; STONE="#a4a598"; OPEN="#5b7778"
plt.rcParams.update({"svg.fonttype":"path", "svg.hashsalt":"ashbound-h01-r2"})

def text(ax,x,y,s,size=10,**kw):
    return ax.text(x,y,s,fontproperties=FONT,fontsize=size,color=INK,**kw)

def dim(ax,a,b,label,vertical=False):
    ax.annotate("",xy=b,xytext=a,arrowprops=dict(arrowstyle="|-|",lw=.8,color=INK))
    x,y=(a[0]+b[0])/2,(a[1]+b[1])/2
    text(ax,x+(.17 if vertical else 0),y+(.12 if not vertical else 0),label,9,ha="left" if vertical else "center",va="center" if vertical else "bottom",rotation=90 if vertical else 0)

def setup(ax,title,xlim,ylim):
    ax.set_facecolor(PAPER)
    ax.set_xlim(*xlim); ax.set_ylim(*ylim); ax.set_aspect("equal"); ax.axis("off")
    ax.set_title(title,fontproperties=FONT,fontsize=14,color=INK,loc="left",pad=9)

def elevation(ax,face):
    b=D['body']; r=D['roof']; gable=face in ('front','rear')
    span=b['width'] if gable else b['depth']; half=span/2
    setup(ax,{'front':'01 / Входной фасад','right':'02 / Правая стена','rear':'03 / Задний фасад','left':'04 / Левая стена'}[face],(-5.2,5.2),(-.85,7.1))
    view_sign=-1 if face in ('rear','left') else 1
    ax.add_patch(Rectangle((-half,0),span,b['wall_top_z'],facecolor=PLASTER,edgecolor=INK,lw=1))
    ax.add_patch(Rectangle((-half,0),span,b['plinth_top_z'],facecolor=STONE,edgecolor=INK,lw=.6))
    if gable:
        ax.add_patch(Polygon([(-half,b['wall_top_z']),(0,r['ridge_z']),(half,b['wall_top_z'])],facecolor=PLASTER,edgecolor=INK,lw=1))
        # The side overhang continues the pitch below the wall plate.
        edge=half+r['overhang_side']; ez=r['ridge_z']-edge*math.tan(math.radians(r['pitch_degrees']))
        ax.plot([-edge,0,edge],[ez,r['ridge_z'],ez],color=WOOD,lw=6,solid_capstyle='butt')
        c=D['chimney']; cx=view_sign*c['centre_xy'][0]
        ax.add_patch(Rectangle((cx-c['footprint_xy'][0]/2,4.6),c['footprint_xy'][0],c['top_z']-4.6,facecolor=STONE,edgecolor=INK,lw=.8,zorder=.5))
    else:
        ex=half+r['overhang_gable']; ez=b['wall_top_z']-r['overhang_side']
        ax.add_patch(Rectangle((-ex,ez),2*ex,r['ridge_z']-ez,facecolor=WOOD,edgecolor=INK,lw=1))
        # Chimney projection; hidden base is intentional in this elevation.
        c=D['chimney']; cx=view_sign*c['centre_xy'][1]
        ax.add_patch(Rectangle((cx-c['footprint_xy'][1]/2,r['ridge_z']),c['footprint_xy'][1],c['top_z']-r['ridge_z'],facecolor=STONE,edgecolor=INK,lw=.8))
    for o in D['openings']:
        if o['face']!=face: continue
        x=view_sign*o['horizontal_center']; z=o['bottom_z']; w=o['width']; h=o['height']
        ax.add_patch(Rectangle((x-w/2,z),w,h,facecolor=OPEN if o['kind']=='window' else WOOD,edgecolor=INK,lw=1))
    if face=='front':
        e=D['entry']; x=next(o for o in D['openings'] if o['id']=='entry')['horizontal_center']
        for i in range(e['steps']):
            ax.plot([x-e['width']/2,x+e['width']/2],[e['rise_each']*(i+1)]*2,color=INK,lw=1)
        ax.plot([x-e['canopy_width']/2,x+e['canopy_width']/2],[e['canopy_front_z']]*2,color=WOOD,lw=5)
    dim(ax,(-half,-.7),(half,-.7),f"{span:g} м")
    if face=='front': dim(ax,(half+.65,0),(half+.65,r['ridge_z']),f"{r['ridge_z']:g} м",True)
    ax.plot([-half-.1,half+.1],[0,0],color=INK,lw=.8)


def plan(ax):
    setup(ax,"05 / Бытовой план и свет",(-4.8,4.8),(-5.7,5.2))
    b=D['body']; t=b['wall_thickness']; hx=b['width']/2; hy=b['depth']/2
    ax.add_patch(Rectangle((-hx,-hy),2*hx,2*hy,facecolor=STONE,edgecolor=INK,lw=1))
    ax.add_patch(Rectangle((-hx+t,-hy+t),2*(hx-t),2*(hy-t),facecolor=PAPER,edgecolor=INK,lw=.6))
    colors=['#dcc8a9','#c6d6c0','#dac2ac','#c7cbd5']
    labels=['Вход\nодежда','Стол\nдневной свет','Очаг\nготовка','Сон\nтихая часть']
    for zone,color,label in zip(D['habitation_zones'],colors,labels):
        x,y,w,h=zone['rect_xy']; ax.add_patch(Rectangle((x,y),w,h,facecolor=color,edgecolor='none'))
        text(ax,x+w/2,y+h/2,label,8,ha='center',va='center')
    for o in D['openings']:
        if o['id'].startswith('attic'):continue
        c=o['horizontal_center']; w=o['width']; face=o['face']
        if face in ('front','rear'):
            y=-hy if face=='front' else hy
            ax.plot([c-w/2,c+w/2],[y,y],color=OPEN,lw=6,solid_capstyle='butt')
        else:
            x=hx if face=='right' else -hx
            ax.plot([x,x],[c-w/2,c+w/2],color=OPEN,lw=6,solid_capstyle='butt')
    e=D['entry']; door=next(o for o in D['openings'] if o['id']=='entry'); x=door['horizontal_center']
    ax.add_patch(Rectangle((x-e['canopy_width']/2,-hy-e['canopy_projection']),e['canopy_width'],e['canopy_projection'],fill=False,edgecolor=WOOD,lw=1,linestyle='--'))
    ax.annotate('',xy=(x,-3.0),xytext=(x,-5.35),arrowprops=dict(arrowstyle='->',color=INK,lw=1.2))
    text(ax,1.0,-5.35,"К улице",9)
    cx,cy=D['chimney']['centre_xy']; wx,wy=D['chimney']['footprint_xy']
    ax.add_patch(Rectangle((cx-wx/2,cy-wy/2),wx,wy,facecolor='#a57358',edgecolor=INK,lw=.8))
    text(ax,0,-.1,"Проход",8,ha='center',rotation=90)
    dim(ax,(-hx,4.65),(hx,4.65),'6 м')
    dim(ax,(3.9,-hy),(3.9,hy),'8 м',True)


def main():
    fig=plt.figure(figsize=(16,11),facecolor=PAPER)
    grid=fig.add_gridspec(2,3,left=.045,right=.97,bottom=.10,top=.85,wspace=.18,hspace=.27)
    for pos,face in zip([(0,0),(0,1),(1,0),(1,1)],['front','right','rear','left']): elevation(fig.add_subplot(grid[pos]),face)
    plan(fig.add_subplot(grid[0,2]))
    ax=fig.add_subplot(grid[1,2]); ax.axis('off')
    lines=[('H01 · размерная опора',15),('Редакция 2 / предложение',10),('',6),
           ('Корпус: 6 × 8 м',11),('Пол +0,36; стены до +3,20 м',10),('Конёк +6,20; дымоход +6,65 м',10),
           ('Свесы: 0,60 сбоку / 0,45 у фронтона',9),('Дверь: 1,15 × 2,20 м',10),('Козырёк: 2,10 × 1,00 м',10),('',6),
           ('Что объясняет внешний вид',12),('Свет — к столу и месту сна.',10),('Дымоход — над кухонным очагом.',10),('Сухой вход — для мокрой одежды.',10),('Дрова — под укрытием у дома.',10),('',6),
           ('H01: предлагается бесшовный вход.',9),('Зоны — план, не готовая механика.',9),('Дверь, замок и сундук — отдельные объекты.',9)]
    y=1
    for line,size in lines:
        ax.text(0,y,line,fontproperties=FONT,fontsize=size,color=INK,transform=ax.transAxes,va='top'); y-=.064 if size>=11 else .058
    fig.text(.045,.945,'AshBound / H01 — дом, устроенный для жизни',fontproperties=FONT,fontsize=25,color=INK)
    fig.text(.045,.901,'Размеры и проёмы для будущего Blender. Предложение: сначала оценка концепта владельцем.',fontproperties=FONT,fontsize=12,color=INK)
    fig.text(.045,.055,'Единицы — метры. Цветные зоны — назначение, а не утверждённые стены. Мебель и двор не включать в базовый меш.',fontproperties=FONT,fontsize=10,color=INK)
    fig.text(.045,.025,'Источник размеров: h01-spec.json · Blender X вправо, Y к задней стене, Z вверх · Игровых изменений нет.',fontproperties=FONT,fontsize=9,color=INK)
    fig.savefig(HERE/'h01-dimensions.svg',metadata={'Date':None})
    svg_path = HERE/'h01-dimensions.svg'
    svg_path.write_text('\n'.join(line.rstrip() for line in svg_path.read_text(encoding='utf-8').splitlines())+'\n', encoding='utf-8', newline='\n')
    fig.savefig(HERE/'h01-dimensions.png',dpi=130)
    plt.close(fig)
    print('Saved measured SVG/PNG; no game geometry generated.')


if __name__=='__main__': main()
