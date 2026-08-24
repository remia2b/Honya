# -*- coding: utf-8 -*-
"""La page de la deuxième chance."""
from catalogue import ecrire

T = {
    "Rien cette fois.": {
        "en": "Nothing this time.", "es": "Nada esta vez.",
        "es-419": "Nada esta vez.", "pt-BR": "Nada desta vez.",
        "de": "Diesmal nichts.", "it": "Niente stavolta.",
        "nl": "Deze keer niets.", "pl": "Tym razem nic.",
        "sv": "Inget den här gången.", "tr": "Bu sefer olmadı.",
        "ru": "В этот раз ничего.", "ja": "今回ははずれ。",
        "ko": "이번엔 꽝이에요.", "zh-Hans": "这次没中。",
    },
    "Une seule autre, et elle est pour vous.": {
        "en": "One more, and it's yours.",
        "es": "Solo una más, y es para ti.",
        "es-419": "Solo una más, y es para ti.",
        "pt-BR": "Só mais uma, e é sua.",
        "de": "Noch ein Versuch, und der gehört dir.",
        "it": "Un solo altro giro, ed è tuo.",
        "nl": "Nog één, en die is voor jou.",
        "pl": "Jeszcze jedna, i jest Twoja.",
        "sv": "Ett till, och det är ditt.",
        "tr": "Bir hakkın daha var, o da senin.",
        "ru": "Ещё одна попытка — она ваша.",
        "ja": "もう一度だけ、あなたのために。",
        "ko": "딱 한 번 더, 당신을 위해.",
        "zh-Hans": "还有一次机会，属于你。",
    },
    "Votre deuxième chance": {
        "en": "Your second chance", "es": "Tu segunda oportunidad",
        "es-419": "Tu segunda oportunidad", "pt-BR": "Sua segunda chance",
        "de": "Deine zweite Chance", "it": "La tua seconda occasione",
        "nl": "Je tweede kans", "pl": "Twoja druga szansa",
        "sv": "Din andra chans", "tr": "İkinci şansın",
        "ru": "Ваш второй шанс", "ja": "二度目のチャンス",
        "ko": "두 번째 기회", "zh-Hans": "你的第二次机会",
    },
    "Celui-ci est le bon. Faites-la tourner.": {
        "en": "This one's the one. Give it a spin.",
        "es": "Este es el bueno. Hazla girar.",
        "es-419": "Este es el bueno. Hazla girar.",
        "pt-BR": "Esta é a boa. Gire a roda.",
        "de": "Dieser ist der richtige. Dreh sie.",
        "it": "Questo è quello buono. Falla girare.",
        "nl": "Deze is de goede. Draai maar.",
        "pl": "Ten będzie ten. Zakręć.",
        "sv": "Det här är rätt. Snurra på.",
        "tr": "Bu sefer tuttu. Çevir bakalım.",
        "ru": "Вот этот — тот самый. Крутите.",
        "ja": "これが当たり。回してみて。",
        "ko": "이번이 그 순간이에요. 돌려 보세요.",
        "zh-Hans": "就是这一次，转吧。",
    },
}

if __name__ == "__main__":
    ecrire(T)
