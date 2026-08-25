# -*- coding: utf-8 -*-
"""Le bandeau d'invitation et la porte d'entrée dans les réglages."""
from catalogue import ecrire

T = {
    "Passez à Honya+": {
        "en": "Go Honya+", "es": "Pásate a Honya+", "es-419": "Pásate a Honya+",
        "pt-BR": "Assine o Honya+", "de": "Auf Honya+ umsteigen",
        "it": "Passa a Honya+", "nl": "Ga naar Honya+",
        "pl": "Przejdź na Honya+", "sv": "Byt till Honya+",
        "tr": "Honya+'a geç", "ru": "Перейти на Honya+",
        "ja": "Honya+ にする", "ko": "Honya+로 업그레이드",
        "zh-Hans": "升级到 Honya+",
    },
    "Un tome ajouté, tout le rayon se pose.": {
        "en": "Add one volume, the whole shelf lands.",
        "es": "Añade un tomo y se coloca toda la serie.",
        "es-419": "Agrega un tomo y se acomoda toda la serie.",
        "pt-BR": "Adicione um volume e a série inteira aparece.",
        "de": "Ein Band genügt, die ganze Reihe steht da.",
        "it": "Aggiungi un volume, l'intero scaffale si compone.",
        "nl": "Eén deel toevoegen en de hele plank staat er.",
        "pl": "Dodaj jeden tom, ustawi się cała półka.",
        "sv": "Lägg till en volym, hela hyllan ställer sig.",
        "tr": "Bir cilt ekle, raf kendiliğinden dizilsin.",
        "ru": "Добавьте один том — встанет вся полка.",
        "ja": "一巻を足せば、棚がまるごと並ぶ。",
        "ko": "한 권만 넣으면 서가가 통째로 채워져요.",
        "zh-Hans": "添一卷，整排书自己就位。",
    },
    "Rayons complets, alertes, historique entier.": {
        "en": "Full shelves, alerts, complete history.",
        "es": "Series completas, avisos, historial entero.",
        "es-419": "Series completas, avisos, historial entero.",
        "pt-BR": "Séries completas, alertas, histórico inteiro.",
        "de": "Vollständige Reihen, Alarme, ganzer Verlauf.",
        "it": "Scaffali completi, avvisi, storico intero.",
        "nl": "Volle planken, meldingen, hele geschiedenis.",
        "pl": "Pełne półki, powiadomienia, cała historia.",
        "sv": "Fulla hyllor, aviseringar, hela historiken.",
        "tr": "Tam raflar, bildirimler, eksiksiz geçmiş.",
        "ru": "Полные полки, уведомления, вся история.",
        "ja": "全巻の棚、発売通知、全期間の記録。",
        "ko": "완성된 서가, 발매 알림, 전체 기록.",
        "zh-Hans": "完整书架、发售提醒、全部记录。",
    },
    "Votre abonnement est actif.": {
        "en": "Your subscription is active.",
        "es": "Tu suscripción está activa.",
        "es-419": "Tu suscripción está activa.",
        "pt-BR": "Sua assinatura está ativa.",
        "de": "Dein Abo ist aktiv.", "it": "Il tuo abbonamento è attivo.",
        "nl": "Je abonnement is actief.", "pl": "Twoja subskrypcja jest aktywna.",
        "sv": "Din prenumeration är aktiv.", "tr": "Aboneliğin etkin.",
        "ru": "Ваша подписка активна.", "ja": "サブスクリプションは有効です。",
        "ko": "구독이 활성화되어 있어요.", "zh-Hans": "你的订阅已生效。",
    },
    "Sur l'appareil": {
        "en": "On this device", "es": "En el dispositivo",
        "es-419": "En el dispositivo", "pt-BR": "No aparelho",
        "de": "Auf dem Gerät", "it": "Sul dispositivo", "nl": "Op dit apparaat",
        "pl": "Na urządzeniu", "sv": "På enheten", "tr": "Bu cihazda",
        "ru": "На устройстве", "ja": "この端末内", "ko": "이 기기에",
        "zh-Hans": "本机存储",
    },
}

if __name__ == "__main__":
    ecrire(T)
