# -*- coding: utf-8 -*-
"""Le renvoi du courrier de confirmation."""
from catalogue import ecrire

T = {
    "Renvoyer le courrier de confirmation": {
        "en": "Send the confirmation email again",
        "es": "Reenviar el correo de confirmación",
        "es-419": "Reenviar el correo de confirmación",
        "pt-BR": "Reenviar o e-mail de confirmação",
        "de": "Bestätigungsmail erneut senden",
        "it": "Invia di nuovo l'e-mail di conferma",
        "nl": "Bevestigingsmail opnieuw sturen",
        "pl": "Wyślij ponownie e-mail potwierdzający",
        "sv": "Skicka bekräftelsemejlet igen",
        "tr": "Doğrulama e-postasını yeniden gönder",
        "ru": "Отправить письмо подтверждения ещё раз",
        "ja": "確認メールを再送する",
        "ko": "확인 메일 다시 보내기",
        "zh-Hans": "重新发送确认邮件",
    },
    "Un nouveau courrier de confirmation vient de partir.": {
        "en": "A new confirmation email is on its way.",
        "es": "Acabamos de enviarte otro correo de confirmación.",
        "es-419": "Acabamos de enviarte otro correo de confirmación.",
        "pt-BR": "Um novo e-mail de confirmação acabou de sair.",
        "de": "Eine neue Bestätigungsmail ist unterwegs.",
        "it": "Una nuova e-mail di conferma è appena partita.",
        "nl": "Er is net een nieuwe bevestigingsmail verstuurd.",
        "pl": "Nowy e-mail potwierdzający właśnie poleciał.",
        "sv": "Ett nytt bekräftelsemejl är på väg.",
        "tr": "Yeni bir doğrulama e-postası yola çıktı.",
        "ru": "Новое письмо подтверждения уже в пути.",
        "ja": "確認メールをもう一度お送りしました。",
        "ko": "확인 메일을 다시 보냈어요.",
        "zh-Hans": "新的确认邮件已经发出。",
    },
}

if __name__ == "__main__":
    ecrire(T)
