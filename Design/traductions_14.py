# -*- coding: utf-8 -*-
"""Le rayon complet et la mémoire longue des statistiques."""
from catalogue import ecrire

T = {
    "Poser le rayon entier": {
        "en": "Shelve the whole series", "es": "Colocar la serie entera",
        "es-419": "Colocar la serie completa", "pt-BR": "Montar a série inteira",
        "de": "Die ganze Reihe einräumen", "it": "Comporre l'intera serie",
        "nl": "De hele reeks neerzetten", "pl": "Ustaw całą serię",
        "sv": "Ställ upp hela serien", "tr": "Serinin tamamını diz",
        "ru": "Расставить всю серию", "ja": "シリーズ全巻を並べる",
        "ko": "시리즈 전권 정리하기", "zh-Hans": "整理整套系列",
    },
    "Tous les tomes parus et à venir, dates comprises.": {
        "en": "Every volume out and upcoming, release dates included.",
        "es": "Todos los tomos publicados y por venir, con sus fechas.",
        "es-419": "Todos los tomos publicados y por salir, con sus fechas.",
        "pt-BR": "Todos os volumes lançados e futuros, com as datas.",
        "de": "Alle erschienenen und kommenden Bände, mit Terminen.",
        "it": "Tutti i volumi usciti e in arrivo, date comprese.",
        "nl": "Alle verschenen en komende delen, met datums.",
        "pl": "Wszystkie wydane i nadchodzące tomy, z datami.",
        "sv": "Alla utgivna och kommande volymer, med datum.",
        "tr": "Çıkmış ve çıkacak tüm ciltler, tarihleriyle birlikte.",
        "ru": "Все вышедшие и будущие тома, с датами выхода.",
        "ja": "既刊も新刊も、発売日つきで。",
        "ko": "출간된 권도 나올 권도, 발매일까지.",
        "zh-Hans": "已出与待出的每一卷，含发售日期。",
    },
    "Ouvrir tout l'historique": {
        "en": "Open your full history", "es": "Abrir todo el historial",
        "es-419": "Abrir todo el historial", "pt-BR": "Abrir todo o histórico",
        "de": "Den gesamten Verlauf öffnen", "it": "Aprire tutto lo storico",
        "nl": "De hele geschiedenis openen", "pl": "Otwórz całą historię",
        "sv": "Öppna hela historiken", "tr": "Tüm geçmişi aç",
        "ru": "Открыть всю историю", "ja": "全期間の記録を見る",
        "ko": "전체 기록 열기", "zh-Hans": "查看全部记录",
    },
}

if __name__ == "__main__":
    ecrire(T)
