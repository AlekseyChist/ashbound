"""Build the offline AshBound UI reference from local, versioned sources.

Requires reportlab. PDF and HTML use the same drawing commands, font and tokens.
This is a documentation builder; it does not change any Godot resource.
"""
from pathlib import Path
import base64
import html
import json

from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
T = json.loads((HERE / "tokens.json").read_text(encoding="utf-8"))
C = {k: v["hex"] for k, v in T["colors"].items()}
W, H = 1280, 720
BG, NOTE = "#17191D", "#BBB8AE"  # Editorial page colors, not game tokens.
pdfmetrics.registerFont(TTFont("AshBoundUI", str(HERE / T["font"]["file"])))
FONT = "AshBoundUI"
OUT = canvas.Canvas(str(HERE / "AshBound-UI-Book.pdf"), pagesize=(W, H), pageCompression=1)
OUT.setTitle("AshBound — Книга интерфейса 1.0")
OUT.setAuthor("AshBound / UI-BOOK-01")
OUT.setSubject("Локальные образцы интерфейса, параметры и правила применения")
PAGES = []
SVG = []
TEXT_RECORDS = []


def rect(x, y, width, height, fill, stroke=None, radius=0, border=1):
    assert x >= 0 and y >= 0 and x + width <= W and y + height <= H
    OUT.setFillColor(HexColor(fill))
    OUT.setLineWidth(border)
    if stroke:
        OUT.setStrokeColor(HexColor(stroke))
    OUT.roundRect(x, H-y-height, width, height, radius, fill=1, stroke=int(bool(stroke)))
    SVG.append(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{border}"/>')


def line(x1, y1, x2, y2, color=None, width=1):
    color = color or C["border"]
    OUT.setStrokeColor(HexColor(color)); OUT.setLineWidth(width)
    OUT.line(x1, H-y1, x2, H-y2)
    SVG.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}"/>')


def text(x, y, value, size=24, color=None, max_width=None):
    color = color or C["text"]
    value = str(value)
    width = pdfmetrics.stringWidth(value, FONT, size)
    assert x >= 0 and y >= 0 and x+width <= W-24, (len(PAGES)+1, value, x+width)
    assert y+size <= H-18, (value, y)
    if max_width is not None:
        assert width <= max_width, (value, width, max_width)
    OUT.setFont(FONT, size); OUT.setFillColor(HexColor(color))
    OUT.drawString(x, H-y-size, value)
    SVG.append(f'<text x="{x}" y="{y+size}" font-size="{size}" fill="{color}">{html.escape(value)}</text>')
    TEXT_RECORDS.append({"page":len(PAGES)+1,"text":value,"x":x,"y":y,"width":width,"size":size})


def para(x, y, value, width, size=23, color=None, leading=None):
    leading = leading or size*1.42
    for paragraph in value.split("\n"):
        words, current = paragraph.split(), ""
        for word in words:
            candidate = (current+" "+word).strip()
            if current and pdfmetrics.stringWidth(candidate, FONT, size)>width:
                text(x,y,current,size,color,max_width=width); y+=leading; current=word
            else:
                current=candidate
        if current: text(x,y,current,size,color,max_width=width); y+=leading
        y += leading*.25
    return y


def button(x,y,label="Блок",state="normal",width=None,height=None):
    g=T["geometry"]
    width=width or g["button_minimum"][0]; height=height or g["button_minimum"][1]
    fill = C["pressed"] if state in ("pressed","selected") else C.get(state,C["normal"])
    color = C["disabled_text"] if state=="disabled" else C["text"]
    stroke=C["border"]; border=g["button_border"]
    if state=="focus": stroke=C["text"]; border=g["focus_border"]["width"]
    if state=="cue": color=C["cue_text"]; stroke=C["cue_border"]; border=g["cue_border"]
    rect(x,y,width,height,fill,stroke,g["button_radius"],border)
    fs=T["font"]["sizes"]["action"]
    tw=pdfmetrics.stringWidth(label,FONT,fs)
    assert tw+2*g["button_padding"][0]<=width
    text(x+(width-tw)/2,y+(height-fs)/2-3,label,fs,color)
    if state=="selected":
        # Use an explicit mark: this font's check glyph has no visible outline.
        line(x+width-30,y+20,x+width-24,y+26,C["text"],2)
        line(x+width-24,y+26,x+width-14,y+14,C["text"],2)


def panel(x,y,width,height):
    g=T["geometry"]
    rect(x,y,width,height,C["panel"],C["border"],g["panel_radius"],g["panel_border"])


def begin(title,sub):
    global SVG
    SVG=[]
    rect(0,0,W,H,BG)
    text(52,30,"AshBound  /  UI 1.0",17,C["border"])
    text(52,66,title,40)
    text(52,126,sub,21,NOTE,max_width=1160)
    OUT.bookmarkPage(f"page-{len(PAGES)+1}")
    OUT.addOutlineEntry(title,f"page-{len(PAGES)+1}",level=0)


def end(title):
    line(52,672,1228,672,"#4B4740")
    text(52,683,"Локальная опора • значения в логических единицах Godot • образцы до переноса в игру",14,NOTE)
    text(1186,681,f"{len(PAGES)+1:02d}",18,C["border"])
    PAGES.append((title,'\n'.join(SVG)))
    OUT.showPage()


begin("Книга интерфейса", "Общий образец для HUD, меню и боевых действий")
text(52,204,"Один шрифт. Общие размеры. Предсказуемые состояния.",31)
button(52,291,"Удар")
button(316,291,"Блок")
button(580,291,"Бег", "selected")
para(866,286,"Тёмная поверхность\nБронзовый контур\nСветлый текст",334,25)
para(52,474,"Основа: действующий интерфейс 0.18.3. Образцы сохраняют его палитру и шрифт; разрозненные решения получают общие правила.",1130,25)
para(52,584,"В APK ещё «БЛОК». Эта книга задаёт «Блок»; применение к игре — отдельная проверяемая задача.",1160,21,NOTE)
end("Книга интерфейса")

begin("Типографика", "Open Sans SemiBold • текущий шрифт Godot • кириллица и латиница")
rows=[("Заголовок страницы","page_title","Персонаж / Character"),
      ("Заголовок раздела","section_title","Снаряжение / Equipment"),
      ("Действие и основной текст","action","Блок / Block · Удар / Attack"),
      ("Вторичный текст","secondary","Удерживай для защиты / Hold to guard"),
      ("Номер быстрого слота","slot_index","1 2 3 4 5 6 7 8 9 0"),
      ("Короткое пояснение","caption","Ёж, щит, рюкзак / Gear, shield, pack")]
for i,(label,key,sample) in enumerate(rows):
    yy=184+i*66; fs=T['font']['sizes'][key]
    text(52,yy+6,label,20,NOTE)
    text(368,yy+6,fs,22,C['border'])
    text(438,yy,sample,fs,max_width=790)
    line(52,yy+58,1228,yy+58,'#36383C')
para(52,611,"У кнопки всегда 30. При нехватке места меняем контейнер или формулировку; размер и регистр не скачут.",1150,20,NOTE)
end("Типографика")

begin("Палитра и материалы", "HEX для просмотра • исходные RGB и прозрачность сохранены в tokens.json")
swatches=[('panel','Панель'),('normal','Кнопка'),('hover','Наведение'),('pressed','Нажатие'),('border','Рамка'),('text','Текст')]
for i,(key,label) in enumerate(swatches):
    xx=52+(i%3)*405; yy=190+(i//3)*196
    rect(xx,yy,356,76,C[key])
    text(xx,yy+88,label,27)
    alpha=T['colors'][key].get('alpha',1)
    text(xx,yy+127,f"{C[key]}  ·  α {alpha:g}",19,NOTE)
para(52,604,"Цвет сигнала окна блока используется кратко в бою. Обычные кнопки сохраняют спокойную палитру.",1160,22,NOTE)
end("Палитра и материалы")

begin("Кнопки и состояния", "Шрифт 30 и размер 240×120 • выбранный режим показан на кнопке «Бег»")
states=[('normal','Обычная'),('hover','Наведение'),('pressed','Нажата / удерживается'),('selected','Режим выбран'),('disabled','Недоступна'),('focus','Фокус клавиатуры')]
for i,(state,label) in enumerate(states):
    xx=52+(i%3)*405; yy=202+(i//3)*204
    button(xx,yy,label='Бег' if state=='selected' else 'Блок',state=state)
    text(xx,yy+134,label,22)
para(52,614,"Disabled и focus — образцы нормализации для переноса. Галочка относится к выбранному режиму, а не к удержанию блока.",1160,18,NOTE)
end("Кнопки и состояния")

begin("Размеры и отступы", "1920×1080 — базовый viewport • логические единицы не равны пикселям телефона")
button(92,256)
line(92,235,332,235); line(92,228,92,242); line(332,228,332,242)
text(183,195,"240 min",22,C['border'])
line(360,256,360,376); line(352,256,368,256); line(352,376,368,376)
text(376,296,"120 min",22,C['border'])
text(92,400,"Радиус 8 · рамка 1 · текст 30",22)
text(92,438,"Внутренние поля 12×8",22,NOTE)
panel(658,214,538,288)
text(684,239,"Общий контейнер",32,C['border'])
button(684,320,'Удар',width=240)
button(936,320,'Блок',width=240)
text(684,459,"Между элементами 12",22,NOTE)
para(52,539,"Минимум не задаёт фиксированную ширину. Длинная подпись расширяет кнопку; изменение сетки проходит проверку обеих локалей.",1130,23)
text(52,621,"От безопасной области до UI — 24. Схема контейнера справа условная, не макет нового экрана.",19,NOTE)
end("Размеры и отступы")

begin("Панели и содержимое", "Одна палитра и иерархия • образцы компонентов, без изменения игрового меню")
panel(52,195,568,374)
text(78,218,"Снаряжение",32,C['border'])
text(78,272,"Одежда, оружие и носимые ёмкости",24)
line(78,319,594,319,'#4B4740')
text(78,347,"Рюкзак",30)
text(78,394,"Содержимое доступно, когда он надет",22,NOTE)
button(78,436,'Открыть',width=240,height=120)
panel(660,195,568,374)
text(686,218,"Equipment",32,C['border'])
text(686,272,"Outfit, weapon and carried storage",24)
line(686,319,1202,319,'#4B4740')
text(686,347,"Backpack",30)
text(686,394,"Contents are available while equipped",22,NOTE)
button(686,436,'Open',width=240,height=120)
para(52,598,"Поля панели 14×10 — базовый минимум. В примере добавлен отступ группы; ширина действий 240, высота 120.",1160,20,NOTE)
end("Панели и содержимое")

begin("Сигнал окна блока", "Обычный блок и своевременное нажатие используют одно название действия")
button(52,257,state='normal')
button(468,257,state='pressed')
button(884,257,state='cue')
text(52,397,"Готовность",27)
text(468,397,"Удержание",27)
text(884,397,"Окно точного блока",27)
para(52,448,"Нейтральная поверхность",290,22,NOTE)
para(468,448,"Тёплая заливка\nБез нового регистра",290,22,NOTE)
para(884,448,"Янтарный фон\nСветлая рамка 3",290,22,NOTE)
para(52,567,"Никакого «БЛОК!» и изменения кегля на вспышке. Сигнал включается только по фактическому боевому окну; его длительность здесь не меняем.",1150,24)
end("Сигнал окна блока")

begin("Надписи на двух языках", "Названия действий начинаются с прописной буквы • клавиши сохраняют свои обозначения")
text(52,190,"Используем",25,C['border']); text(659,190,"Не переносим в новые образцы",25,C['border'])
rows=[('Блок / Block','БЛОК / BLOCK'),('Удар / Attack','УДАР!!! / ATTACK!!!'),('Бег / Run','разный размер у одной кнопки'),('ПКМ / RMB · WASD · 1–0','искусственный upper() для всего UI')]
for i,(good,bad) in enumerate(rows):
    yy=248+i*76
    text(52,yy,good,30 if i<3 else 27)
    text(659,yy,bad,26,NOTE)
    line(52,yy+55,1228,yy+55,'#36383C')
para(52,589,"Название хранится в каталоге локализации. Перед переносом сверяем ключ, контекст и реальные подписи EN/RU.",1160,23,NOTE)
end("Надписи на двух языках")

begin("Текущий билд и применение", "Снимок 0.18.3 до стандарта • он показывает исходное состояние, а не готовую миграцию")
shot=ROOT/'docs/art/cons-02b/pc-after-running.png'
OUT.drawImage(str(shot),52,H-201-360,width=640,height=360,mask='auto')
image_data=base64.b64encode(shot.read_bytes()).decode('ascii')
SVG.append(f'<image x="52" y="201" width="640" height="360" href="data:image/png;base64,{image_data}"/>')
para(750,193,"Сначала меняем подписи защиты и подключаем общие роли HUD. Затем отдельно переносим настройки и инвентарь.",468,25)
para(750,344,"В карточке: версия книги, роли параметров, состояния, EN/RU. Для Qwen — точные исходники и нужная страница.",468,23,NOTE)
para(750,484,"Codex проверяет diff и игру на ПК и актуальной APK. Личный отзыв владельца записывается отдельно.",468,23,NOTE)
text(52,598,"Источники: HUD, панель защиты, настройки, инвентарь и быстрые слоты",20,NOTE)
text(52,630,"Исходные пути и отличия от стандарта: README.md и tokens.json рядом с этой книгой",18,NOTE)
end("Текущий билд и применение")

OUT.save()
woff=base64.b64encode((HERE/T['font']['web_file']).read_bytes()).decode('ascii')
nav=''.join(f'<a href="#page-{i}">{i:02d} {html.escape(title)}</a>' for i,(title,_) in enumerate(PAGES,1))
sections=''.join(f'<section id="page-{i}" aria-label="{html.escape(title)}"><svg viewBox="0 0 {W} {H}" role="img" aria-labelledby="title-{i}"><title id="title-{i}">{html.escape(title)}</title>{svg}</svg></section>' for i,(title,svg) in enumerate(PAGES,1))
document=f'''<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AshBound — Книга интерфейса 1.0</title>
<style>@font-face{{font-family:AshBoundUI;src:url(data:font/woff2;base64,{woff}) format('woff2');font-weight:600}}
*{{box-sizing:border-box}}body{{margin:0;background:{BG};color:{C['text']};font-family:AshBoundUI,sans-serif;font-weight:600}}
header{{padding:24px;max-width:1280px;margin:auto}}h1{{font-size:28px;margin:0 0 12px}}nav{{display:flex;flex-wrap:wrap;gap:10px 20px}}a{{color:{C['border']};font-size:16px}}a:focus-visible{{outline:2px solid {C['text']};outline-offset:4px}}
main{{max-width:1280px;margin:auto}}section{{margin:0 0 20px;scroll-margin:12px}}svg{{display:block;width:100%;height:auto;font-family:AshBoundUI,sans-serif;font-weight:600}}
@media(max-width:700px){{main{{overflow-x:auto}}section{{min-width:960px}}header p{{font-size:16px}}}}
@media print{{@page{{size:16in 9in;margin:0}}header{{display:none}}main{{max-width:none}}section{{margin:0;break-after:page;min-width:0}}section:last-child{{break-after:auto}}}}
</style></head><body><header><h1>Книга интерфейса AshBound</h1><p>Версия 1.0 · автономный файл · для небольшого экрана удобнее PDF с масштабированием.</p><nav aria-label="Страницы">{nav}</nav></header><main>{sections}</main></body></html>'''
(HERE/'index.html').write_text(document,encoding='utf-8')
print(f'BUILT {len(PAGES)} pages, {len(TEXT_RECORDS)} text blocks; all text within page bounds')
print('PDF:',HERE/'AshBound-UI-Book.pdf')
print('HTML:',HERE/'index.html')
