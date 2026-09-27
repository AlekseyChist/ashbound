const LAB = {
  "schema": 1,
  "canvas": 627,
  "poses": {
    "a0": {
      "file": "probe-a-sheet.png",
      "rect": [
        0,
        0,
        627,
        627
      ],
      "label": "Контакт A",
      "pivot": [
        353.0,
        598.0
      ]
    },
    "a1": {
      "file": "probe-a-sheet.png",
      "rect": [
        627,
        0,
        627,
        627
      ],
      "label": "Ранний перенос A",
      "pivot": [
        276.0,
        607.0
      ]
    },
    "a2": {
      "file": "probe-a-sheet.png",
      "rect": [
        0,
        627,
        627,
        627
      ],
      "label": "Контакт B — прежний",
      "pivot": [
        361.0,
        576.0
      ]
    },
    "a3": {
      "file": "probe-a-sheet.png",
      "rect": [
        627,
        627,
        627,
        627
      ],
      "label": "Проход A",
      "pivot": [
        277.0,
        585.0
      ]
    },
    "b": {
      "file": "probe-b-passing.png",
      "rect": [
        0,
        0,
        1254,
        1254
      ],
      "label": "Проход B",
      "pivot": [
        278.0,
        587.0
      ]
    },
    "d": {
      "file": "probe-d-contact.png",
      "rect": [
        0,
        0,
        1254,
        1254
      ],
      "label": "Контакт B",
      "pivot": [
        355.0,
        598.5
      ]
    },
    "e0": {
      "file": "probe-e-sheet.png",
      "rect": [
        0,
        0,
        627,
        627
      ],
      "label": "Перенос A",
      "pivot": [
        348.0,
        610.0
      ]
    },
    "e1": {
      "file": "probe-e-sheet.png",
      "rect": [
        627,
        0,
        627,
        627
      ],
      "label": "Вынос B",
      "pivot": [
        324.0,
        605.0
      ]
    },
    "e2": {
      "file": "probe-e-sheet.png",
      "rect": [
        0,
        627,
        627,
        627
      ],
      "label": "Перенос B",
      "pivot": [
        356.0,
        597.0
      ]
    },
    "e3": {
      "file": "probe-e-sheet.png",
      "rect": [
        627,
        627,
        627,
        627
      ],
      "label": "Вынос A",
      "pivot": [
        323.0,
        590.0
      ]
    },
    "f": {
      "file": "probe-f-arms.png",
      "rect": [
        0,
        0,
        1254,
        1254
      ],
      "label": "Вынос B",
      "pivot": [
        324.0,
        605.5
      ]
    }
  },
  "variants": {
    "raw": {
      "frames": [
        "a0",
        "a1",
        "a2",
        "a3"
      ],
      "note": "Первая проба A — отклонена: подписи фаз не совпали с рисунками, повторилась опорная нога."
    },
    "keys": {
      "frames": [
        "a0",
        "a3",
        "d",
        "b"
      ],
      "note": "Четыре ключа после исправления перекрытия ноги и второй контактной позы. Грубая проверка двух шагов."
    },
    "final": {
      "frames": [
        "a0",
        "e0",
        "a3",
        "f",
        "d",
        "e2",
        "b",
        "e3"
      ],
      "note": "Текущий кандидат: восемь цельных рисунков, два шага. Проверяем движение и постоянство формы; в игру пока не подключён."
    }
  },
  "notes": "Whole drawings translated only: head silhouette right edge has common X; sole has common Y. One fixed normalization from source cell resolution to 627 units. No pose-specific fitting, body-part transforms, color changes or morphing."
};
