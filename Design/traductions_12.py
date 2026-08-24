# -*- coding: utf-8 -*-
"""Les compteurs de limites du gratuit."""
from catalogue import ecrire

T = {
    "%lld sur %lld": {
        "en": "%lld of %lld", "es": "%lld de %lld", "es-419": "%lld de %lld",
        "pt-BR": "%lld de %lld", "de": "%lld von %lld", "it": "%lld su %lld",
        "nl": "%lld van %lld", "pl": "%lld z %lld", "sv": "%lld av %lld",
        "tr": "%lld / %lld", "ru": "%lld из %lld", "ja": "%lld／%lld",
        "ko": "%lld / %lld", "zh-Hans": "%lld / %lld",
    },
    "%lld scans restants": {
        "en": "%lld scans left",
        "es": "Quedan %lld escaneos", "es-419": "Quedan %lld escaneos",
        "pt-BR": "Restam %lld leituras", "de": "Noch %lld Scans",
        "it": "%lld scansioni rimaste", "nl": "Nog %lld scans",
        "pl": "Pozostało %lld skanów", "sv": "%lld skanningar kvar",
        "tr": "%lld tarama kaldı", "ru": "Осталось %lld сканирований",
        "ja": "残り%lld回", "ko": "%lld회 남음", "zh-Hans": "还剩 %lld 次",
    },
}

if __name__ == "__main__":
    ecrire(T)
