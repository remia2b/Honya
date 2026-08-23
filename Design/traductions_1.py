# -*- coding: utf-8 -*-
"""Traductions — vague 1 : navigation, statuts, actions courantes.

Voix de Honya : chaleureuse et directe, jamais bavarde. On tutoie le
vocabulaire du livre (rayon, tome, étagère) plutôt que celui du logiciel.
"""
from catalogue import ecrire

T = {
    # ------------------------------------------------------------ onglets
    "Aujourd'hui": {
        "en": "Today", "es": "Hoy", "es-419": "Hoy", "pt-BR": "Hoje",
        "de": "Heute", "it": "Oggi", "pl": "Dziś", "ja": "今日",
    },
    "Bibliothèque": {
        "en": "Library", "es": "Biblioteca", "es-419": "Biblioteca",
        "pt-BR": "Biblioteca", "de": "Bibliothek", "it": "Libreria",
        "pl": "Biblioteka", "ja": "ライブラリ",
    },
    "Découverte": {
        "en": "Discover", "es": "Descubrir", "es-419": "Descubrir",
        "pt-BR": "Descobrir", "de": "Entdecken", "it": "Scopri",
        "pl": "Odkrywaj", "ja": "見つける",
    },
    "Stats": {
        "en": "Stats", "es": "Datos", "es-419": "Datos", "pt-BR": "Dados",
        "de": "Statistik", "it": "Statistiche", "pl": "Statystyki", "ja": "統計",
    },
    "Statistiques": {
        "en": "Statistics", "es": "Estadísticas", "es-419": "Estadísticas",
        "pt-BR": "Estatísticas", "de": "Statistiken", "it": "Statistiche",
        "pl": "Statystyki", "ja": "統計",
    },
    "Recherche": {
        "en": "Search", "es": "Buscar", "es-419": "Buscar", "pt-BR": "Buscar",
        "de": "Suchen", "it": "Cerca", "pl": "Szukaj", "ja": "検索",
    },
    "Réglages": {
        "en": "Settings", "es": "Ajustes", "es-419": "Configuración",
        "pt-BR": "Ajustes", "de": "Einstellungen", "it": "Impostazioni",
        "pl": "Ustawienia", "ja": "設定",
    },
    "Collections": {
        "en": "Collections", "es": "Colecciones", "es-419": "Colecciones",
        "pt-BR": "Coleções", "de": "Sammlungen", "it": "Raccolte",
        "pl": "Kolekcje", "ja": "コレクション",
    },

    # ------------------------------------------------------------ statuts
    "À lire": {
        "en": "To read", "es": "Por leer", "es-419": "Por leer",
        "pt-BR": "Para ler", "de": "Ungelesen", "it": "Da leggere",
        "pl": "Do przeczytania", "ja": "未読",
    },
    "En cours": {
        "en": "Reading", "es": "Leyendo", "es-419": "Leyendo",
        "pt-BR": "Lendo", "de": "Aktuell", "it": "In lettura",
        "pl": "W trakcie", "ja": "読書中",
    },
    "Lu": {
        "en": "Read", "es": "Leído", "es-419": "Leído", "pt-BR": "Lido",
        "de": "Gelesen", "it": "Letto", "pl": "Przeczytane", "ja": "読了",
    },
    "Abandonné": {
        "en": "Abandoned", "es": "Abandonado", "es-419": "Abandonado",
        "pt-BR": "Abandonado", "de": "Abgebrochen", "it": "Abbandonato",
        "pl": "Porzucone", "ja": "中断",
    },
    "À acheter": {
        "en": "To buy", "es": "Por comprar", "es-419": "Por comprar",
        "pt-BR": "Para comprar", "de": "Zu kaufen", "it": "Da comprare",
        "pl": "Do kupienia", "ja": "購入予定",
    },
    "lu": {
        "en": "read", "es": "leído", "es-419": "leído", "pt-BR": "lido",
        "de": "gelesen", "it": "letto", "pl": "przeczytany", "ja": "読了",
    },
    "possédé": {
        "en": "owned", "es": "en mi estantería", "es-419": "en mi estantería",
        "pt-BR": "na estante", "de": "im Regal", "it": "posseduto",
        "pl": "na półce", "ja": "所有",
    },
    "manquant": {
        "en": "missing", "es": "falta", "es-419": "falta", "pt-BR": "falta",
        "de": "fehlt", "it": "mancante", "pl": "brakuje", "ja": "未所持",
    },

    # ------------------------------------------------------- types & formats
    "Livre": {
        "en": "Book", "es": "Libro", "es-419": "Libro", "pt-BR": "Livro",
        "de": "Buch", "it": "Libro", "pl": "Książka", "ja": "書籍",
    },
    "Manga": {
        "en": "Manga", "es": "Manga", "es-419": "Manga", "pt-BR": "Mangá",
        "de": "Manga", "it": "Manga", "pl": "Manga", "ja": "マンガ",
    },
    "BD": {
        "en": "Comics", "es": "Cómic", "es-419": "Cómic", "pt-BR": "HQ",
        "de": "Comic", "it": "Fumetto", "pl": "Komiks", "ja": "コミック",
    },
    "Série": {
        "en": "Series", "es": "Serie", "es-419": "Serie", "pt-BR": "Série",
        "de": "Reihe", "it": "Serie", "pl": "Seria", "ja": "シリーズ",
    },
    "Séries": {
        "en": "Series", "es": "Series", "es-419": "Series", "pt-BR": "Séries",
        "de": "Reihen", "it": "Serie", "pl": "Serie", "ja": "シリーズ",
    },
    "Poche": {
        "en": "Paperback", "es": "Bolsillo", "es-419": "Bolsillo",
        "pt-BR": "Bolso", "de": "Taschenbuch", "it": "Tascabile",
        "pl": "Kieszonkowe", "ja": "文庫",
    },
    "Grand format": {
        "en": "Trade edition", "es": "Edición grande", "es-419": "Edición grande",
        "pt-BR": "Edição grande", "de": "Großformat", "it": "Formato grande",
        "pl": "Duży format", "ja": "単行本",
    },
    "Relié": {
        "en": "Hardcover", "es": "Tapa dura", "es-419": "Tapa dura",
        "pt-BR": "Capa dura", "de": "Gebunden", "it": "Rilegato",
        "pl": "Twarda oprawa", "ja": "ハードカバー",
    },
    "Numérique": {
        "en": "Digital", "es": "Digital", "es-419": "Digital",
        "pt-BR": "Digital", "de": "Digital", "it": "Digitale",
        "pl": "Cyfrowe", "ja": "電子書籍",
    },
    "Audio": {
        "en": "Audiobook", "es": "Audiolibro", "es-419": "Audiolibro",
        "pt-BR": "Audiolivro", "de": "Hörbuch", "it": "Audiolibro",
        "pl": "Audiobook", "ja": "オーディオブック",
    },
    "En cours de parution": {
        "en": "Ongoing", "es": "En publicación", "es-419": "En publicación",
        "pt-BR": "Em publicação", "de": "Läuft noch", "it": "In corso",
        "pl": "W trakcie wydawania", "ja": "連載中",
    },
    "Terminée": {
        "en": "Complete", "es": "Finalizada", "es-419": "Finalizada",
        "pt-BR": "Concluída", "de": "Abgeschlossen", "it": "Conclusa",
        "pl": "Zakończona", "ja": "完結",
    },
    "Parution inconnue": {
        "en": "Status unknown", "es": "Publicación desconocida",
        "es-419": "Publicación desconocida", "pt-BR": "Publicação desconhecida",
        "de": "Status unbekannt", "it": "Pubblicazione sconosciuta",
        "pl": "Nieznany status", "ja": "刊行状況不明",
    },

    # ------------------------------------------------------ actions courantes
    "Ajouter": {
        "en": "Add", "es": "Añadir", "es-419": "Agregar", "pt-BR": "Adicionar",
        "de": "Hinzufügen", "it": "Aggiungi", "pl": "Dodaj", "ja": "追加",
    },
    "Annuler": {
        "en": "Cancel", "es": "Cancelar", "es-419": "Cancelar",
        "pt-BR": "Cancelar", "de": "Abbrechen", "it": "Annulla",
        "pl": "Anuluj", "ja": "キャンセル",
    },
    "OK": {
        "en": "OK", "es": "OK", "es-419": "OK", "pt-BR": "OK",
        "de": "OK", "it": "OK", "pl": "OK", "ja": "OK",
    },
    "Enregistrer": {
        "en": "Save", "es": "Guardar", "es-419": "Guardar", "pt-BR": "Salvar",
        "de": "Sichern", "it": "Salva", "pl": "Zapisz", "ja": "保存",
    },
    "Modifier": {
        "en": "Edit", "es": "Editar", "es-419": "Editar", "pt-BR": "Editar",
        "de": "Bearbeiten", "it": "Modifica", "pl": "Edytuj", "ja": "編集",
    },
    "Supprimer": {
        "en": "Delete", "es": "Eliminar", "es-419": "Eliminar",
        "pt-BR": "Excluir", "de": "Löschen", "it": "Elimina",
        "pl": "Usuń", "ja": "削除",
    },
    "Retirer": {
        "en": "Remove", "es": "Quitar", "es-419": "Quitar", "pt-BR": "Remover",
        "de": "Entfernen", "it": "Rimuovi", "pl": "Usuń", "ja": "取り除く",
    },
    "Continuer": {
        "en": "Continue", "es": "Continuar", "es-419": "Continuar",
        "pt-BR": "Continuar", "de": "Weiter", "it": "Continua",
        "pl": "Dalej", "ja": "続ける",
    },
    "Ignorer": {
        "en": "Skip", "es": "Omitir", "es-419": "Omitir", "pt-BR": "Pular",
        "de": "Überspringen", "it": "Salta", "pl": "Pomiń", "ja": "スキップ",
    },
    "Appliquer": {
        "en": "Apply", "es": "Aplicar", "es-419": "Aplicar", "pt-BR": "Aplicar",
        "de": "Anwenden", "it": "Applica", "pl": "Zastosuj", "ja": "適用",
    },
    "Créer": {
        "en": "Create", "es": "Crear", "es-419": "Crear", "pt-BR": "Criar",
        "de": "Erstellen", "it": "Crea", "pl": "Utwórz", "ja": "作成",
    },
    "Chercher": {
        "en": "Search", "es": "Buscar", "es-419": "Buscar", "pt-BR": "Buscar",
        "de": "Suchen", "it": "Cerca", "pl": "Szukaj", "ja": "検索",
    },
    "Tout": {
        "en": "All", "es": "Todo", "es-419": "Todo", "pt-BR": "Tudo",
        "de": "Alle", "it": "Tutto", "pl": "Wszystko", "ja": "すべて",
    },
    "Tout voir": {
        "en": "See all", "es": "Ver todo", "es-419": "Ver todo",
        "pt-BR": "Ver tudo", "de": "Alle ansehen", "it": "Vedi tutto",
        "pl": "Zobacz wszystko", "ja": "すべて表示",
    },
    "Plus": {
        "en": "More", "es": "Más", "es-419": "Más", "pt-BR": "Mais",
        "de": "Mehr", "it": "Altro", "pl": "Więcej", "ja": "もっと見る",
    },
    "Réduire": {
        "en": "Less", "es": "Menos", "es-419": "Menos", "pt-BR": "Menos",
        "de": "Weniger", "it": "Meno", "pl": "Mniej", "ja": "閉じる",
    },
    "Lire la suite": {
        "en": "Read more", "es": "Leer más", "es-419": "Leer más",
        "pt-BR": "Ler mais", "de": "Weiterlesen", "it": "Continua a leggere",
        "pl": "Czytaj dalej", "ja": "続きを読む",
    },
    "Trier par": {
        "en": "Sort by", "es": "Ordenar por", "es-419": "Ordenar por",
        "pt-BR": "Ordenar por", "de": "Sortieren nach", "it": "Ordina per",
        "pl": "Sortuj według", "ja": "並べ替え",
    },
    "Statut": {
        "en": "Status", "es": "Estado", "es-419": "Estado", "pt-BR": "Status",
        "de": "Status", "it": "Stato", "pl": "Status", "ja": "ステータス",
    },
    "Note": {
        "en": "Rating", "es": "Valoración", "es-419": "Calificación",
        "pt-BR": "Avaliação", "de": "Bewertung", "it": "Voto",
        "pl": "Ocena", "ja": "評価",
    },
    "Noter": {
        "en": "Rate", "es": "Valorar", "es-419": "Calificar",
        "pt-BR": "Avaliar", "de": "Bewerten", "it": "Vota",
        "pl": "Oceń", "ja": "評価する",
    },
    "Pages": {
        "en": "Pages", "es": "Páginas", "es-419": "Páginas",
        "pt-BR": "Páginas", "de": "Seiten", "it": "Pagine",
        "pl": "Strony", "ja": "ページ",
    },
    "Chapitres": {
        "en": "Chapters", "es": "Capítulos", "es-419": "Capítulos",
        "pt-BR": "Capítulos", "de": "Kapitel", "it": "Capitoli",
        "pl": "Rozdziały", "ja": "話数",
    },
    "Minutes": {
        "en": "Minutes", "es": "Minutos", "es-419": "Minutos",
        "pt-BR": "Minutos", "de": "Minuten", "it": "Minuti",
        "pl": "Minuty", "ja": "分",
    },
    "min": {
        "en": "min", "es": "min", "es-419": "min", "pt-BR": "min",
        "de": "Min.", "it": "min", "pl": "min", "ja": "分",
    },
    "Jour": {
        "en": "Day", "es": "Día", "es-419": "Día", "pt-BR": "Dia",
        "de": "Tag", "it": "Giorno", "pl": "Dzień", "ja": "日",
    },
    "Semaine": {
        "en": "Week", "es": "Semana", "es-419": "Semana", "pt-BR": "Semana",
        "de": "Woche", "it": "Settimana", "pl": "Tydzień", "ja": "週",
    },
    "Mois": {
        "en": "Month", "es": "Mes", "es-419": "Mes", "pt-BR": "Mês",
        "de": "Monat", "it": "Mese", "pl": "Miesiąc", "ja": "月",
    },
    "Année": {
        "en": "Year", "es": "Año", "es-419": "Año", "pt-BR": "Ano",
        "de": "Jahr", "it": "Anno", "pl": "Rok", "ja": "年",
    },
    "Période": {
        "en": "Period", "es": "Periodo", "es-419": "Periodo",
        "pt-BR": "Período", "de": "Zeitraum", "it": "Periodo",
        "pl": "Okres", "ja": "期間",
    },
    "Portée": {
        "en": "Scope", "es": "Ámbito", "es-419": "Ámbito", "pt-BR": "Escopo",
        "de": "Bereich", "it": "Ambito", "pl": "Zakres", "ja": "範囲",
    },
    "Honya": {
        "en": "Honya", "es": "Honya", "es-419": "Honya", "pt-BR": "Honya",
        "de": "Honya", "it": "Honya", "pl": "Honya", "ja": "Honya",
    },
    "Application": {
        "en": "App", "es": "Aplicación", "es-419": "Aplicación",
        "pt-BR": "App", "de": "App", "it": "App", "pl": "Aplikacja",
        "ja": "アプリ",
    },
    "Version": {
        "en": "Version", "es": "Versión", "es-419": "Versión",
        "pt-BR": "Versão", "de": "Version", "it": "Versione",
        "pl": "Wersja", "ja": "バージョン",
    },
}

if __name__ == "__main__":
    ecrire(T)
