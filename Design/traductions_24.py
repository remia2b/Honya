# -*- coding: utf-8 -*-
"""Les marches de l'escalier de connexion."""
from catalogue import ecrire

T = {
    "Valider le code": {
        "en": "Check the code", "es": "Validar el código",
        "es-419": "Validar el código", "pt-BR": "Validar o código",
        "de": "Code prüfen", "it": "Verifica il codice",
        "nl": "Code controleren", "pl": "Sprawdź kod",
        "sv": "Kontrollera koden", "tr": "Kodu doğrula",
        "ru": "Проверить код", "ja": "コードを確認",
        "ko": "코드 확인", "zh-Hans": "验证代码",
    },
    "Choisissez votre nouveau mot de passe.": {
        "en": "Pick your new password.",
        "es": "Elige tu nueva contraseña.",
        "es-419": "Elige tu nueva contraseña.",
        "pt-BR": "Escolha sua nova senha.",
        "de": "Wähle dein neues Passwort.",
        "it": "Scegli la tua nuova password.",
        "nl": "Kies je nieuwe wachtwoord.",
        "pl": "Wybierz nowe hasło.",
        "sv": "Välj ditt nya lösenord.",
        "tr": "Yeni parolanı seç.",
        "ru": "Выберите новый пароль.",
        "ja": "新しいパスワードを決めてください。",
        "ko": "새 비밀번호를 정하세요.",
        "zh-Hans": "设置你的新密码。",
    },
    "Recommencez : le code n'a pas été vérifié.": {
        "en": "Start over: the code wasn't verified.",
        "es": "Vuelve a empezar: el código no se verificó.",
        "es-419": "Vuelve a empezar: el código no se verificó.",
        "pt-BR": "Recomece: o código não foi verificado.",
        "de": "Fang neu an: der Code wurde nicht geprüft.",
        "it": "Ricomincia: il codice non è stato verificato.",
        "nl": "Begin opnieuw: de code is niet gecontroleerd.",
        "pl": "Zacznij od nowa: kod nie został zweryfikowany.",
        "sv": "Börja om: koden verifierades inte.",
        "tr": "Baştan başla: kod doğrulanmadı.",
        "ru": "Начните заново: код не был проверен.",
        "ja": "やり直してください。コードが確認されていません。",
        "ko": "처음부터 다시 해주세요. 코드가 확인되지 않았어요.",
        "zh-Hans": "请重新开始：验证码未通过校验。",
    },
}

if __name__ == "__main__":
    ecrire(T)
