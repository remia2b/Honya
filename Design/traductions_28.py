# -*- coding: utf-8 -*-
"""Le retour de la boîte aux lettres."""
from catalogue import ecrire

T = {
    "Adresse confirmée. Connectez-vous.": {
        "en": "Address confirmed. Sign in.",
        "es": "Dirección confirmada. Inicia sesión.",
        "es-419": "Dirección confirmada. Inicia sesión.",
        "pt-BR": "Endereço confirmado. Entre na sua conta.",
        "de": "Adresse bestätigt. Melde dich an.",
        "it": "Indirizzo confermato. Accedi.",
        "nl": "Adres bevestigd. Log in.",
        "pl": "Adres potwierdzony. Zaloguj się.",
        "sv": "Adressen är bekräftad. Logga in.",
        "tr": "Adres doğrulandı. Giriş yap.",
        "ru": "Адрес подтверждён. Войдите.",
        "ja": "メールアドレスを確認しました。サインインしてください。",
        "ko": "주소가 확인됐어요. 로그인하세요.",
        "zh-Hans": "地址已确认，请登录。",
    },
}

if __name__ == "__main__":
    ecrire(T)
