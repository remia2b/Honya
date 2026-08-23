# -*- coding: utf-8 -*-
"""Traductions — vague 5 : les dernières clés, et une correction.

`%lld trouvé%@` vient d'un ancien bricolage de pluriel, remplacé dans le
code : la clé est laissée traduite le temps que le catalogue soit purgé.
"""
from catalogue import ecrire

T = {
    "Scanner": {
        "en": "Scan", "es": "Escanear", "es-419": "Escanear", "pt-BR": "Escanear",
        "de": "Scannen", "it": "Scansiona", "pl": "Skanuj", "ja": "スキャン",
    },
    "Reprendre la lecture": {
        "en": "Resume reading", "es": "Reanudar la lectura",
        "es-419": "Reanudar la lectura", "pt-BR": "Retomar a leitura",
        "de": "Weiterlesen", "it": "Riprendi la lettura",
        "pl": "Wznów czytanie", "ja": "読書を再開",
    },
    "Tome %lld": {
        "en": "Volume %lld", "es": "Tomo %lld", "es-419": "Tomo %lld",
        "pt-BR": "Volume %lld", "de": "Band %lld", "it": "Volume %lld",
        "pl": "Tom %lld", "ja": "%lld巻",
    },
    "Lu jusqu'au chapitre %lld": {
        "en": "Read up to chapter %lld", "es": "Leído hasta el capítulo %lld",
        "es-419": "Leído hasta el capítulo %lld", "pt-BR": "Lido até o capítulo %lld",
        "de": "Gelesen bis Kapitel %lld", "it": "Letto fino al capitolo %lld",
        "pl": "Przeczytane do rozdziału %lld", "ja": "第%lld話まで読了",
    },
    "sur %lld min · aujourd'hui": {
        "en": "of %lld min · today", "es": "de %lld min · hoy",
        "es-419": "de %lld min · hoy", "pt-BR": "de %lld min · hoje",
        "de": "von %lld Min. · heute", "it": "su %lld min · oggi",
        "pl": "z %lld min · dzisiaj", "ja": "%lld分中 · 今日",
    },
    "%lld trouvé%@": {
        "en": "%lld found%@", "es": "%lld encontrado%@", "es-419": "%lld encontrado%@",
        "pt-BR": "%lld encontrado%@", "de": "%lld gefunden%@",
        "it": "%lld trovato%@", "pl": "znaleziono %lld%@", "ja": "%lld件%@",
    },

    # Correction : un mot russe s'était glissé dans la version japonaise.
    "Lisez chaque jour : la série grandit et les statistiques suivent.": {
        "ja": "毎日読めば記録は伸び、統計もついてきます。",
    },
}

if __name__ == "__main__":
    ecrire(T)
