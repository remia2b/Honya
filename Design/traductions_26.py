# -*- coding: utf-8 -*-
"""L'accueil refait : le rang de l'étape et la durée libre."""
from catalogue import ecrire

T = {
    "Étape %lld sur 3": {
        "en": "Step %lld of 3", "es": "Paso %lld de 3",
        "es-419": "Paso %lld de 3", "pt-BR": "Etapa %lld de 3",
        "de": "Schritt %lld von 3", "it": "Passo %lld di 3",
        "nl": "Stap %lld van 3", "pl": "Krok %lld z 3",
        "sv": "Steg %lld av 3", "tr": "3 adımdan %lld.",
        "ru": "Шаг %lld из 3", "ja": "ステップ %lld / 3",
        "ko": "%lld단계 / 3", "zh-Hans": "第 %lld 步，共 3 步",
    },
    "Autre durée": {
        "en": "Another length", "es": "Otra duración",
        "es-419": "Otra duración", "pt-BR": "Outra duração",
        "de": "Andere Dauer", "it": "Altra durata",
        "nl": "Andere duur", "pl": "Inny czas",
        "sv": "Annan längd", "tr": "Başka bir süre",
        "ru": "Другая длительность", "ja": "ほかの長さ",
        "ko": "다른 시간", "zh-Hans": "其他时长",
    },
    "Quelques minutes par jour suffisent à construire une série.": {
        "en": "A few minutes a day is enough to build a streak.",
        "es": "Bastan unos minutos al día para construir una racha.",
        "es-419": "Bastan unos minutos al día para construir una racha.",
        "pt-BR": "Alguns minutos por dia bastam para criar uma sequência.",
        "de": "Ein paar Minuten am Tag genügen für eine Serie.",
        "it": "Bastano pochi minuti al giorno per costruire una serie.",
        "nl": "Een paar minuten per dag is genoeg voor een reeks.",
        "pl": "Kilka minut dziennie wystarczy, by zbudować passę.",
        "sv": "Några minuter om dagen räcker för en svit.",
        "tr": "Günde birkaç dakika bir seri kurmaya yeter.",
        "ru": "Нескольких минут в день хватает, чтобы собрать серию.",
        "ja": "一日数分で連続記録は続きます。",
        "ko": "하루 몇 분이면 연속 기록이 쌓여요.",
        "zh-Hans": "每天几分钟，就能连成一串。",
    },
}

if __name__ == "__main__":
    ecrire(T)
