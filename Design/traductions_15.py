# -*- coding: utf-8 -*-
"""Le statut choisi d'une série, et le prêt d'un tome."""
from catalogue import ecrire

T = {
    "Calculé d'après vos tomes": {
        "en": "Worked out from your volumes",
        "es": "Deducido de tus tomos", "es-419": "Deducido de tus tomos",
        "pt-BR": "Deduzido dos seus volumes",
        "de": "Aus deinen Bänden abgeleitet",
        "it": "Dedotto dai tuoi volumi",
        "nl": "Afgeleid uit je delen",
        "pl": "Wyliczony z Twoich tomów",
        "sv": "Härlett från dina volymer",
        "tr": "Ciltlerinden çıkarıldı",
        "ru": "Выведено из ваших томов",
        "ja": "巻の状況から判定", "ko": "보유 권수로 판단",
        "zh-Hans": "根据你的卷数推断",
    },
    "Choisi par vous": {
        "en": "Set by you", "es": "Elegido por ti", "es-419": "Elegido por ti",
        "pt-BR": "Definido por você", "de": "Von dir festgelegt",
        "it": "Scelto da te", "nl": "Door jou gekozen",
        "pl": "Wybrany przez Ciebie", "sv": "Vald av dig",
        "tr": "Senin seçimin", "ru": "Выбрано вами",
        "ja": "あなたが設定", "ko": "직접 설정함", "zh-Hans": "由你设定",
    },
    "Laisser Honya décider": {
        "en": "Let Honya decide", "es": "Dejar que Honya decida",
        "es-419": "Dejar que Honya decida", "pt-BR": "Deixar o Honya decidir",
        "de": "Honya entscheiden lassen", "it": "Lascia decidere a Honya",
        "nl": "Laat Honya beslissen", "pl": "Niech Honya zdecyduje",
        "sv": "Låt Honya avgöra", "tr": "Honya karar versin",
        "ru": "Пусть решает Honya", "ja": "Honyaにまかせる",
        "ko": "Honya에게 맡기기", "zh-Hans": "交给 Honya 判断",
    },
    "Prêter ce tome…": {
        "en": "Lend this volume…", "es": "Prestar este tomo…",
        "es-419": "Prestar este tomo…", "pt-BR": "Emprestar este volume…",
        "de": "Diesen Band verleihen …", "it": "Presta questo volume…",
        "nl": "Dit deel uitlenen…", "pl": "Pożycz ten tom…",
        "sv": "Låna ut den här volymen…", "tr": "Bu cildi ödünç ver…",
        "ru": "Одолжить этот том…", "ja": "この巻を貸す…",
        "ko": "이 권 빌려주기…", "zh-Hans": "借出这一卷…",
    },
    "Prêté à %@": {
        "en": "Lent to %@", "es": "Prestado a %@", "es-419": "Prestado a %@",
        "pt-BR": "Emprestado a %@", "de": "Verliehen an %@",
        "it": "Prestato a %@", "nl": "Uitgeleend aan %@",
        "pl": "Pożyczone: %@", "sv": "Utlånad till %@",
        "tr": "%@ kişisine ödünç verildi", "ru": "Одолжена: %@",
        "ja": "%@ に貸出中", "ko": "%@ 님에게 빌려줌", "zh-Hans": "借给了 %@",
    },
}

if __name__ == "__main__":
    ecrire(T)
