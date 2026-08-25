# -*- coding: utf-8 -*-
"""Deux textes qui s'affichaient en français dans toutes les langues."""
from catalogue import ecrire

T = {
    "Retour": {
        "en": "Back", "es": "Atrás", "es-419": "Atrás", "pt-BR": "Voltar",
        "de": "Zurück", "it": "Indietro", "nl": "Terug", "pl": "Wstecz",
        "sv": "Tillbaka", "tr": "Geri", "ru": "Назад", "ja": "戻る",
        "ko": "뒤로", "zh-Hans": "返回",
    },
    "Se déconnecter garde votre bibliothèque sur cet appareil. Supprimer votre compte l'efface. Pour retirer Honya de votre identifiant Apple, allez dans Réglages > votre nom > Connexion avec Apple.": {
        "en": "Signing out keeps your library on this device. Deleting your account erases it. To remove Honya from your Apple Account, go to Settings > your name > Sign in with Apple.",
        "es": "Cerrar sesión mantiene tu biblioteca en el dispositivo. Eliminar la cuenta la borra. Para quitar Honya de tu cuenta de Apple, ve a Ajustes > tu nombre > Iniciar sesión con Apple.",
        "es-419": "Cerrar sesión mantiene tu biblioteca en el dispositivo. Eliminar la cuenta la borra. Para quitar Honya de tu cuenta de Apple, ve a Configuración > tu nombre > Iniciar sesión con Apple.",
        "pt-BR": "Sair mantém sua estante neste aparelho. Excluir a conta apaga tudo. Para remover o Honya da sua Conta Apple, vá em Ajustes > seu nome > Iniciar sessão com a Apple.",
        "de": "Beim Abmelden bleibt deine Bibliothek auf dem Gerät. Beim Löschen des Accounts verschwindet sie. Um Honya von deinem Apple-Account zu trennen, geh zu Einstellungen > dein Name > Mit Apple anmelden.",
        "it": "Uscire lascia la tua biblioteca su questo dispositivo. Eliminare l'account la cancella. Per togliere Honya dal tuo account Apple, vai in Impostazioni > il tuo nome > Accedi con Apple.",
        "nl": "Uitloggen laat je bibliotheek op dit apparaat staan. Je account verwijderen wist hem. Ga naar Instellingen > je naam > Inloggen met Apple om Honya van je Apple-account te halen.",
        "pl": "Wylogowanie zostawia bibliotekę na tym urządzeniu. Usunięcie konta ją kasuje. Aby odłączyć Honyę od konta Apple, wejdź w Ustawienia > Twoje imię > Zaloguj się z Apple.",
        "sv": "Att logga ut behåller biblioteket på enheten. Att radera kontot tar bort det. Gå till Inställningar > ditt namn > Logga in med Apple för att koppla bort Honya.",
        "tr": "Çıkış yapmak kitaplığını bu cihazda bırakır. Hesabını silmek onu da siler. Honya'yı Apple hesabından kaldırmak için Ayarlar > adın > Apple ile Giriş Yap yolunu izle.",
        "ru": "Выход сохраняет библиотеку на устройстве. Удаление аккаунта стирает её. Чтобы отвязать Honya от аккаунта Apple, откройте Настройки > ваше имя > Вход с Apple.",
        "ja": "サインアウトしても本棚はこの端末に残ります。アカウントを削除すると消えます。Apple アカウントから Honya を外すには、設定 > 名前 > Apple でサインイン、と進んでください。",
        "ko": "로그아웃해도 서재는 이 기기에 남아요. 계정을 삭제하면 함께 지워져요. Apple 계정에서 Honya를 빼려면 설정 > 이름 > Apple로 로그인으로 가세요.",
        "zh-Hans": "退出登录会把书库留在这台设备上，删除账户则会一并抹去。要把 Honya 从 Apple 账户中移除，请前往「设置 > 你的名字 > 使用 Apple 登录」。",
    },
}

if __name__ == "__main__":
    ecrire(T)
