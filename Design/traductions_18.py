# -*- coding: utf-8 -*-
"""Le cinquième statut à l'ajout."""
from catalogue import ecrire

T = {
    "Je l'ai abandonné": {
        "en": "I gave up on it", "es": "Lo abandoné", "es-419": "Lo abandoné",
        "pt-BR": "Eu abandonei", "de": "Ich habe es abgebrochen",
        "it": "L'ho abbandonato", "nl": "Ik ben ermee gestopt",
        "pl": "Porzuciłem/am", "sv": "Jag gav upp den",
        "tr": "Yarıda bıraktım", "ru": "Я его бросил",
        "ja": "読むのをやめた", "ko": "읽다가 그만뒀어요", "zh-Hans": "我弃读了",
    },
}

if __name__ == "__main__":
    ecrire(T)
