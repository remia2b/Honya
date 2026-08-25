# -*- coding: utf-8 -*-
"""Le défi annuel, qui restait en français partout."""
from catalogue import ecrire

T = {
    "%lld lectures": {
        "en": "%lld books", "es": "%lld lecturas", "es-419": "%lld lecturas",
        "pt-BR": "%lld leituras", "de": "%lld Bücher", "it": "%lld letture",
        "nl": "%lld boeken", "pl": "%lld lektur", "sv": "%lld böcker",
        "tr": "%lld kitap", "ru": "%lld книг", "ja": "%lld冊",
        "ko": "%lld권", "zh-Hans": "%lld 本",
    },
}

if __name__ == "__main__":
    ecrire(T)
