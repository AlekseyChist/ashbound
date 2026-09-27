"""Offline vector concept sheets. Python 3 + reportlab; no game resources changed.

Coordinates, functions and dimensions are proposals, not approved world data.
The source Watabou screenshots are retained byte-for-byte, never processed here.
"""
from pathlib import Path
import base64
import hashlib
import html
import json
import math
import random

from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FONT = ROOT / "assets/ui/fonts/OpenSans-SemiBold.ttf"
pdfmetrics.registerFont(TTFont("AshOpen", str(FONT)))
FONT_DATA = base64.b64encode(FONT.read_bytes()).decode()
W, H = 1440, 1040
C = dict(paper="#F3EFE3", ink="#243A34", muted="#657268", border="#CCC7B5",
         ground="#DEDCC6", woods="#ACB99E", leaf="#6C8269", deep="#425D4D",
         path="#CAB088", roof="#986F50", edge="#654D3D", blue="#618A95",
         gold="#AB793C", red="#A06954", soft="#E4CFBE", panel="#EAE5D6")


class Sheet:
    def __init__(self, pdf):
        self.pdf = pdf
        self.svg = []
        self.ox = self.oy = 0

    def point(self, x, y):
        return x + self.ox, y + self.oy

    def begin_map(self):
        self.pdf.saveState()
        path=self.pdf.beginPath()
        path.rect(48,H-174-700,900,700)
        self.pdf.clipPath(path,stroke=0,fill=0)
        self.svg.append('<defs><clipPath id="mapclip"><rect x="48" y="174" width="900" height="700"/></clipPath></defs><g clip-path="url(#mapclip)">')
        self.ox,self.oy=48,174

    def end_map(self):
        self.ox=self.oy=0
        self.pdf.restoreState()
        self.svg.append('</g>')

    def style(self, fill=None, stroke=None, width=1, dash=None):
        if fill:
            self.pdf.setFillColor(HexColor(fill))
        if stroke:
            self.pdf.setStrokeColor(HexColor(stroke))
        self.pdf.setLineWidth(width)
        self.pdf.setLineCap(1)
        self.pdf.setLineJoin(1)
        self.pdf.setDash(dash or [])
        attrs = f'fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{width}"'
        if dash:
            attrs += f' stroke-dasharray="{" ".join(map(str, dash))}"'
        return attrs

    def rect(self, x, y, w, h, fill, stroke=None, radius=0):
        x, y = self.point(x, y)
        st = self.style(fill, stroke)
        self.pdf.roundRect(x, H-y-h, w, h, radius, fill=bool(fill), stroke=bool(stroke))
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" {st}/>')

    def poly(self, points, fill=None, stroke=None, width=1, closed=True, dash=None):
        pts = [self.point(x, y) for x, y in points]
        st = self.style(fill, stroke, width, dash)
        path = self.pdf.beginPath()
        path.moveTo(pts[0][0], H-pts[0][1])
        for x, y in pts[1:]:
            path.lineTo(x, H-y)
        if closed:
            path.close()
        self.pdf.drawPath(path, fill=bool(fill), stroke=bool(stroke))
        tag = "polygon" if closed else "polyline"
        self.svg.append(f'<{tag} points="{" ".join(f"{x},{y}" for x,y in pts)}" {st} stroke-linecap="round" stroke-linejoin="round"/>')

    def line(self, points, stroke, width=1, dash=None):
        self.poly(points, stroke=stroke, width=width, closed=False, dash=dash)

    def ellipse(self, x, y, rx, ry, fill, stroke=None, width=1):
        x, y = self.point(x, y)
        st = self.style(fill, stroke, width)
        self.pdf.ellipse(x-rx, H-y-ry, x+rx, H-y+ry, fill=bool(fill), stroke=bool(stroke))
        self.svg.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" {st}/>')

    def text(self, x, y, value, size=18, color=None, align="left"):
        x, y = self.point(x, y)
        color = color or C["ink"]
        self.pdf.setFillColor(HexColor(color))
        self.pdf.setFont("AshOpen", size)
        {"left": self.pdf.drawString, "center": self.pdf.drawCentredString, "right": self.pdf.drawRightString}[align](x, H-y, value)
        anchor = {"left": "start", "center": "middle", "right": "end"}[align]
        self.svg.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" text-anchor="{anchor}">{html.escape(value)}</text>')

    def para(self, x, y, value, width=390, size=19, leading=29, color=None):
        line = ""
        for word in value.split():
            test = (line + " " + word).strip()
            if pdfmetrics.stringWidth(test, "AshOpen", size) > width and line:
                self.text(x, y, line, size, color)
                y += leading
                line = word
            else:
                line = test
        if line:
            self.text(x, y, line, size, color)
        return y + leading

    def label(self, x, y, value, size=17, color=None):
        w = pdfmetrics.stringWidth(value, "AshOpen", size) + 20
        self.rect(x-10, y-size-4, w, size+14, C["paper"], radius=4)
        self.text(x, y, value, size, color)

    def badge(self, x, y, value):
        self.ellipse(x, y, 15, 15, C["ink"])
        self.text(x, y+6, str(value), 17, C["paper"], "center")

    def save_svg(self, filename):
        style = f'<style>@font-face{{font-family:AshOpen;src:url(data:font/ttf;base64,{FONT_DATA})}}text{{font-family:AshOpen,sans-serif}}</style>'
        (HERE / filename).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{style}' + "\n".join(self.svg) + '</svg>\n', encoding="utf-8", newline="\n")


def inside(x, y, points):
    result = False
    j = len(points)-1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        if (yi > y) != (yj > y) and x < (xj-xi)*(y-yi)/(yj-yi)+xi:
            result = not result
        j = i
    return result


def woods(s, points, seed=1, density=58):
    s.poly(points, C["woods"])
    rng = random.Random(seed)
    for y in range(26, 690, density):
        for x in range(26, 890, density):
            px, py = x+rng.uniform(-13,13), y+rng.uniform(-13,13)
            if inside(px, py, points):
                s.line([(px,py+14),(px,py+22)], C["deep"], 2)
                s.poly([(px,py-15),(px-12,py+10),(px+12,py+10)], C["leaf"])
                s.poly([(px,py-24),(px-9,py-2),(px+9,py-2)], C["leaf"])


def house(s, x, y, angle=0, badge=None, w=38, h=29):
    a = math.radians(angle)
    def pt(dx,dy):
        return (x+dx*math.cos(a)-dy*math.sin(a), y+dx*math.sin(a)+dy*math.cos(a))
    s.poly([pt(-w/2+3,-h/2+5),pt(w/2+3,-h/2+5),pt(w/2+3,h/2+5),pt(-w/2+3,h/2+5)], "#B6B399")
    s.poly([pt(-w/2,-h/2),pt(w/2,-h/2),pt(w/2,h/2),pt(-w/2,h/2)], C["roof"], C["edge"], 1.5)
    s.line([pt(-w/2,0),pt(w/2,0)], C["edge"], 1.5)
    for dx in (-10,0,10):
        s.line([pt(dx,-h/2+3),pt(dx,h/2-3)], "#B9906A", 1)
    if badge:
        s.badge(x+26, y-22, badge)


def road(s, points, minor=False):
    if minor:
        s.line(points, C["gold"], 4, [8,7])
    else:
        s.line(points, "#B69E78", 19)
        s.line(points, C["path"], 15)


def garden(s,x,y,w,h):
    s.rect(x,y,w,h,"#C4B48C","#A79977")
    for i in range(8,int(h)-5,9):
        s.line([(x+5,y+i),(x+w-5,y+i)], "#A39470", 2)


def header(s, number, title, subtitle):
    s.rect(0,0,W,H,C["paper"])
    s.text(48,45,"ASHBOUND / МИР · КОНЦЕПТ 01",16,C["muted"])
    s.text(1392,45,"24.09.2026 · v1.0",16,C["muted"],"right")
    s.text(48,103,title,42)
    s.text(48,139,subtitle,20,C["muted"])
    s.line([(48,160),(76,160)],C["path"],6)
    s.text(85,165,"дорога",14,C["muted"])
    s.line([(173,160),(203,160)],C["gold"],3,[5,5])
    s.text(212,165,"тропа",14,C["muted"])
    s.text(298,165,"Деревья показаны условно; это лесные массы, а не точная расстановка.",14,C["muted"])
    s.rect(48,174,900,700,C["ground"],C["border"],12)
    s.text(48,988,"ПРЕДЛОЖЕНИЕ · НЕ СОГЛАСОВАНО",17,C["gold"])
    s.text(1392,988,f"{number} / 3",17,C["muted"],"right")
    s.text(48,1018,"Схемы для обсуждения. Геометрия, NPC, задания и услуги по этим листам ещё не создаются.",16,C["muted"])


def north(s):
    s.line([(848,83),(848,38)],C["ink"],2)
    s.poly([(848,31),(842,45),(854,45)],C["ink"])
    s.text(848,24,"С",17,align="center")


def map_scale(s, length, title):
    s.rect(20,641,length+35,42,C["paper"],radius=4)
    s.line([(30,660),(30+length,660)], C["ink"], 3)
    for x in (30,30+length):
        s.line([(x,655),(x,665)],C["ink"],2)
    s.text(35+length/2,680,title,13,align="center")


def notes(s, sections):
    y = 208
    for title, body in sections:
        s.text(990,y,title,23)
        y = s.para(990,y+33,body,size=19,width=394,leading=29)+26
    return y


def village(s, variant):
    a = variant == "a"
    title = "А · Колодезная поляна" if a else "Б · Лесные дворы"
    subtitle = "Компактное поселение вокруг общего места" if a else "Деревня раскрывается по ходу движения"
    header(s,1 if a else 2,title,subtitle)
    s.begin_map()
    if a:
        woods(s,[(0,0),(650,0),(631,107),(521,166),(370,171),(253,238),(148,374),(0,388)],2)
        woods(s,[(0,438),(156,454),(221,573),(217,700),(0,700)],4)
        woods(s,[(720,0),(900,0),(900,700),(604,700),(622,565),(708,480),(743,262)],5)
        for i in range(4):
            s.line([(675+i*27,134),(656+i*26,239),(670+i*28,338),(640+i*30,441)],"#A6AA91",1.5)
        s.poly([(363,295),(424,285),(487,321),(493,387),(444,414),(373,408),(339,352)],"#D9C399")
        road(s,[(415,699),(386,608),(408,533),(411,452),(422,388)])
        road(s,[(453,331),(536,319),(610,268),(662,193),(757,107),(795,0)])
        road(s,[(381,321),(301,286),(239,229),(197,146),(84,48)],True)
        road(s,[(386,608),(335,580),(311,535)],True)
        for x,y,ang,badge in [(350,453,9,1),(305,340,-7,None),(342,263,28,None),(438,245,8,None),(520,288,-30,3),(545,382,-10,None),(477,463,27,None),(336,559,-12,4)]:
            house(s,x,y,ang,badge)
        s.ellipse(425,359,10,10,"#DDD9C9",C["edge"],2)
        s.ellipse(425,359,5,5,C["blue"])
        s.badge(449,340,2)
        garden(s,244,462,55,91)
        garden(s,432,545,68,70)
        s.label(32,42,"К ранней пещере")
        s.label(518,54,"К тракту и таверне")
        s.label(223,114,"Хвойный лес · +8–12 м")
        s.label(639,503,"Склон · +6 м")
        s.label(462,650,"Огороды / конец улицы")
        s.label(259,404,"Общий центр",15)
    else:
        woods(s,[(0,0),(710,0),(690,118),(564,172),(452,201),(339,221),(199,218),(0,162)],12)
        woods(s,[(0,229),(135,252),(177,364),(186,474),(288,522),(260,700),(0,700)],13)
        woods(s,[(736,147),(900,120),(900,700),(419,700),(439,614),(570,544),(637,466),(698,364)],14)
        # A low wooded tongue separates views without blocking the pedestrian loop.
        woods(s,[(384,418),(427,406),(469,449),(483,489),(423,520),(366,499)],15,45)
        for i in range(4):
            s.line([(648+i*28,150),(622+i*27,257),(630+i*27,348),(613+i*28,413)],"#A6AA91",1.5)
        road(s,[(0,229),(134,269),(238,292),(331,330),(445,355),(527,316),(583,224),(628,159),(748,83),(792,0)])
        road(s,[(332,332),(333,410),(309,490),(358,554),(377,699)])
        road(s,[(312,492),(490,555),(550,481),(573,387),(527,316)],True)
        road(s,[(133,269),(149,200),(110,137),(69,52)],True)
        s.ellipse(381,359,28,22,"#D9C399")
        for x,y,ang,badge in [(294,386,-11,1),(215,320,19,None),(321,287,13,None),(433,303,-8,3),(550,268,21,None),(525,410,-18,None),(539,486,20,None),(358,572,-12,4)]:
            house(s,x,y,ang,badge)
        s.ellipse(381,359,9,9,"#DDD9C9",C["edge"],2)
        s.ellipse(381,359,4,4,C["blue"])
        s.badge(406,344,2)
        garden(s,200,370,46,79)
        garden(s,290,544,38,68)
        s.label(26,45,"К ранней пещере")
        s.label(550,56,"К тракту и таверне")
        s.label(222,150,"Лес прячет дальний двор")
        s.label(654,412,"Склон · +8 м")
        s.label(440,597,"Пешая петля между дворами")
        s.label(30,212,"Лесные делянки",15)
    north(s)
    map_scale(s,100,"25 м")
    s.end_map()
    if a:
        sections=[("Что почувствуем","Выходишь из дома и сразу видишь колодец, соседей и оба направления. Тихая поляна, замкнутая плотным лесом."),
                  ("Масштаб предложения","8 строений. Жилое ядро около 90 × 85 м; весь лист 225 × 175 м. Дома 7–10 м, тропы 1–2 м."),
                  ("Назначения на схеме","1 — дом начала игры. 2 — колодец. 3 — мастерская. 4 — общий амбар. Остальные — жилые дворы."),
                  ("Что обсудить","Плюс: легко запомнить место. Риск: слишком ровное кольцо домов может выглядеть постановочно.")]
    else:
        sections=[("Что почувствуем","Из дома виден ближайший двор. За поворотом открывается колодец, затем мастерская. Лес делит деревню на небольшие места."),
                  ("Масштаб предложения","8 строений. Ядро с дворами около 140 × 100 м; весь лист 225 × 175 м. Между домами больше воздуха."),
                  ("Назначения на схеме","1 — дом начала игры. 2 — колодец. 3 — мастерская. 4 — общий амбар. Южная тропа замыкает прогулку."),
                  ("Мой выбор — Б","Лучше подходит лесному началу и исследованию. Колодец и крыша мастерской должны оставаться понятными ориентирами.")]
    notes(s,sections)
    s.text(48,914,"Дерево + каменный цоколь · тёмные крыши · влажная земля · хвойные просветы",19)
    s.text(48,947,"Основа композиции: Watabou. Выходы, назначения, лес и масштаб — предложения AshBound.",16,C["muted"])


def region(s):
    header(s,3,"За деревней · лесная петля","Одинаковые связи для обоих вариантов — выбранная деревня займёт южную поляну")
    s.begin_map()
    woods(s,[(0,0),(900,0),(900,700),(0,700)],21,57)
    # Existing regional geometry is a hypothesis; this sheet changes no source JSON.
    def p(x,z): return (52+x*1.44,34+(z-1050)*1.44)
    def ps(points): return [p(x,z) for x,z in points]
    # Clearings and elevated northern ground.
    s.poly(ps([(38,1123),(178,1085),(252,1116),(207,1178),(118,1220),(48,1205)]),"#C7C8AA")
    for i in range(4):
        s.line(ps([(26,1128+i*19),(108,1088+i*18),(205,1090+i*18),(295,1127+i*18)]),"#9EAC91",1.5)
    s.ellipse(*p(155,1420),77,51,C["ground"])
    s.ellipse(*p(450,1270),48,34,C["ground"])
    main=ps([(400,1080),(415,1150),(420,1210),(460,1280),(510,1340)])
    road(s,main)
    start=[(420,1210),(300,1240),(230,1340),(155,1420)]
    cave=[(155,1420),(95,1330),(75,1230),(115,1170)]
    loop=[(115,1170),(205,1110),(305,1160),(420,1210)]
    for route in (start,cave,loop):
        s.line(ps(route),C["paper"],10)
        road(s,ps(route),True)
    road(s,ps([(420,1210),(450,1270)]))
    # Proposed danger corridor; no impassable or level-locked line.
    s.line(ps([(295,1059),(375,1121),(488,1179),(555,1213)]),C["red"],7,[3,10])
    x,y=p(155,1420)
    for dx,dy,a in [(-30,-12,-10),(12,-22,12),(23,20,-10)]: house(s,x+dx,y+dy,a,w=25,h=20)
    s.badge(x-57,y-30,1)
    x,y=p(115,1170)
    s.poly([(x-18,y+8),(x-9,y-15),(x+9,y-20),(x+22,y+8)],C["muted"])
    s.ellipse(x+2,y+3,8,9,C["ink"])
    s.badge(x-29,y-25,2)
    x,y=p(450,1270)
    house(s,x,y,15,w=43,h=27)
    s.badge(x+27,y-26,3)
    s.label(60,616,"1 · Стартовая деревня")
    s.label(45,266,"2 · Ранняя пещера")
    s.label(621,403,"3 · Лесная таверна")
    s.label(539,61,"К лесному городу")
    s.label(80,73,"Скальный гребень · +30–40 м")
    s.label(443,511,"Местный лес · первые вылазки")
    s.label(373,237,"Дальше — опаснее",17,C["red"])
    s.label(323,148,"Обход через гребень",16)
    north(s)
    map_scale(s,144,"100 м")
    s.end_map()
    notes(s,[("Зачем идти в лес","Из деревни два направления: тропа к ранней пещере и выход к тракту. Возвращаться можно другим путём."),
             ("Естественный заслон","За местным лесом встречаются более сильные враги. Это риск, а не закрытая дверь: можно искать обход или пробежать."),
             ("Таверна — снаружи","На тракте планируются сон, лечение, еда, слухи, задания и сохранение. Услуги проектируем отдельно."),
             ("Расстояния и высоты","Петля с заходом к таверне — около 1 км. Пещера выше деревни примерно на 30 м; весь северный обход ещё выше.")])
    s.text(48,914,"Ранняя пещера — местное исследование. Горная шахта и древние остаются поздней линией.",19)
    s.text(48,947,"Опора: world-exploration-v1. Форма леса и граница опасности предложены только для обсуждения.",16,C["muted"])


def main():
    out = HERE / "AshBound-Starter-Village-Concepts-v1.pdf"
    pdf=canvas.Canvas(str(out),pagesize=(W,H),invariant=1,pageCompression=1)
    pdf.setTitle("AshBound — стартовая деревня: концепты v1.0")
    pdf.setAuthor("AshBound / Codex; village composition studies from Watabou")
    for fn,name in [(lambda s:village(s,"a"),"concept-a.svg"),(lambda s:village(s,"b"),"concept-b.svg"),(region,"forest-connections.svg")]:
        sheet=Sheet(pdf)
        fn(sheet)
        sheet.save_svg(name)
        pdf.showPage()
    pdf.save()
    sources={"status":"b-selected-as-basis-for-refinement", "decision":"DECISION.md", "version":"1.0", "date":"2026-09-24",
             "base_commit":"bb98d0f3b1335e61445a867931abda2bd749ec8f",
             "author_page":"https://watabou.itch.io/village-generator",
             "source_capture":"Browser screenshots, unmodified; include viewport margins. Native SVG export unavailable in this browser session.",
             "source_note":"Same seed, different size/tags. High Drum and population are generator decoration, not AshBound canon.",
             "adaptation":"Concept SVG/PDF are newly authored vector diagrams inspired by the source layouts, not native Watabou exports.",
             "scale":"Both village sheets propose 4 drawing units per metre; regional sheet 1.44 per metre. Watabou dimensions are not asserted to be metres.",
             "font":"assets/ui/fonts/OpenSans-SemiBold.ttf", "variants":{}}
    for key in ("a","b"):
        src=HERE/f"watabou-{key}.png"
        sources["variants"][key]={"url":(HERE/f"watabou-{key}-url.txt").read_text(encoding="utf-8-sig").strip(),
                                 "snapshot":src.name,"sha256":hashlib.sha256(src.read_bytes()).hexdigest()}
    sources["regional_source"]="docs/design/world-exploration-v1/world-exploration.json"
    (HERE/"sources.json").write_text(json.dumps(sources,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    print(out)


if __name__ == "__main__":
    main()
