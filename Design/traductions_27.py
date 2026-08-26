# -*- coding: utf-8 -*-
"""Le scanner dit quand un code est introuvable."""
from catalogue import ecrire

T = {
    "Introuvable dans les catalogues": {
        "en": "Not in any catalog", "es": "No está en los catálogos",
        "es-419": "No está en los catálogos", "pt-BR": "Não está nos catálogos",
        "de": "In keinem Katalog zu finden", "it": "Introvabile nei cataloghi",
        "nl": "Niet in de catalogi", "pl": "Nie ma go w katalogach",
        "sv": "Finns inte i katalogerna", "tr": "Kataloglarda bulunamadı",
        "ru": "Нет ни в одном каталоге", "ja": "カタログに見つかりません",
        "ko": "어느 카탈로그에도 없어요", "zh-Hans": "各目录中都找不到",
    },
    "Certaines éditions n'y figurent pas — cherchez le titre à la main. Ces scans n'ont pas été décomptés.": {
        "en": "Some editions just aren't listed — search the title by hand. These scans weren't counted.",
        "es": "Algunas ediciones no aparecen: busca el título a mano. Estos escaneos no se descontaron.",
        "es-419": "Algunas ediciones no aparecen: busca el título a mano. Estos escaneos no se descontaron.",
        "pt-BR": "Algumas edições simplesmente não constam — busque o título à mão. Esses escaneamentos não foram descontados.",
        "de": "Manche Ausgaben sind schlicht nicht gelistet — such den Titel von Hand. Diese Scans wurden nicht gezählt.",
        "it": "Alcune edizioni semplicemente non ci sono: cerca il titolo a mano. Queste scansioni non sono state contate.",
        "nl": "Sommige uitgaven staan er gewoon niet in — zoek de titel met de hand. Deze scans zijn niet meegeteld.",
        "pl": "Niektórych wydań po prostu tam nie ma — poszukaj tytułu ręcznie. Te skany nie zostały policzone.",
        "sv": "Vissa utgåvor finns helt enkelt inte med — sök titeln för hand. De här skanningarna räknades inte.",
        "tr": "Bazı basımlar kataloglarda yok — başlığı elle ara. Bu taramalar sayılmadı.",
        "ru": "Некоторых изданий там просто нет — поищите название вручную. Эти сканы не были засчитаны.",
        "ja": "カタログに載っていない版もあります。タイトルで検索してください。このスキャンは回数に数えていません。",
        "ko": "목록에 없는 판본도 있어요. 제목으로 직접 검색해 보세요. 이 스캔은 횟수에서 빼지 않았어요.",
        "zh-Hans": "有些版本目录里就是没有——请手动搜索书名。这些扫描没有计入次数。",
    },
}

if __name__ == "__main__":
    ecrire(T)
