# -*- coding: utf-8 -*-
"""Corrections repérées par le contrôle d'alphabets."""
from catalogue import ecrire

T = {
    # « Docmeste » n'était pas un mot : faute de frappe.
    "Où en es-tu ?": {"ru": "На чём остановились?"},
    # « 바코드 » est coréen : en japonais on écrit バーコード.
    "Visez le code-barres au dos du livre": {
        "ja": "本の裏のバーコードにカメラを向けてください",
    },
}

if __name__ == "__main__":
    ecrire(T)
