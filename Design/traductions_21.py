# -*- coding: utf-8 -*-
"""Le statut d'une série à l'ajout, et la puce « Abandonnés »."""
from catalogue import ecrire

T = {
    "Je la possède · à lire": {
        "en": "I own it · to read", "es": "La tengo · por leer",
        "es-419": "La tengo · por leer", "pt-BR": "Eu tenho · para ler",
        "de": "Besitze ich · noch zu lesen", "it": "Ce l'ho · da leggere",
        "nl": "Heb ik · nog lezen", "pl": "Mam ją · do przeczytania",
        "sv": "Jag har den · att läsa", "tr": "Bende var · okunacak",
        "ru": "Есть у меня · прочитать", "ja": "持っている・これから読む",
        "ko": "가지고 있음 · 읽을 예정", "zh-Hans": "已拥有 · 待读",
    },
    "Je suis en train de la lire": {
        "en": "I'm reading it", "es": "La estoy leyendo",
        "es-419": "La estoy leyendo", "pt-BR": "Estou lendo",
        "de": "Lese ich gerade", "it": "La sto leggendo",
        "nl": "Ik lees hem nu", "pl": "Właśnie ją czytam",
        "sv": "Jag läser den nu", "tr": "Şu anda okuyorum",
        "ru": "Читаю сейчас", "ja": "今読んでいる",
        "ko": "지금 읽는 중", "zh-Hans": "正在读",
    },
    "Je l'ai lue": {
        "en": "I've read it", "es": "Ya la leí", "es-419": "Ya la leí",
        "pt-BR": "Já li", "de": "Habe ich gelesen", "it": "L'ho letta",
        "nl": "Heb ik gelezen", "pl": "Przeczytałem ją",
        "sv": "Jag har läst den", "tr": "Okudum", "ru": "Уже прочитал",
        "ja": "読み終えた", "ko": "다 읽었음", "zh-Hans": "已读完",
    },
    "Je l'ai abandonnée": {
        "en": "I gave up on it", "es": "La abandoné", "es-419": "La abandoné",
        "pt-BR": "Abandonei", "de": "Habe ich abgebrochen",
        "it": "L'ho abbandonata", "nl": "Ik ben gestopt",
        "pl": "Porzuciłem ją", "sv": "Jag gav upp den",
        "tr": "Yarıda bıraktım", "ru": "Я её забросил",
        "ja": "読むのをやめた", "ko": "중간에 그만뒀음", "zh-Hans": "弃读了",
    },
    "Abandonnés": {
        "en": "Given up", "es": "Abandonados", "es-419": "Abandonados",
        "pt-BR": "Abandonados", "de": "Abgebrochen", "it": "Abbandonati",
        "nl": "Gestopt", "pl": "Porzucone", "sv": "Uppgivna",
        "tr": "Yarıda kalanlar", "ru": "Заброшенные", "ja": "読むのをやめた本",
        "ko": "그만둔 책", "zh-Hans": "已弃读",
    },
}

if __name__ == "__main__":
    ecrire(T)
