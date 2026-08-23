# Comment Honya est traduit

L'application parle 14 langues. Le français est la langue source : c'est
elle qu'on écrit dans le code, tout le reste en découle.

    fr · en · es · es-419 · pt-BR · de · it · nl · pl · sv · tr · ru · ja · ko · zh-Hans

## La règle

**Une langue à moitié traduite est pire que pas de langue du tout.** Un
lecteur polonais qui tombe sur une phrase française au milieu de son écran
n'y voit pas une traduction en cours, il y voit une application cassée.
D'où le principe : aucun texte n'arrive chez les utilisateurs sans exister
dans les 14 langues.

## Ce qui se passe tout seul

À chaque poussée qui touche du code ou des textes, le travail
`.github/workflows/traductions.yml` fait la chaîne complète :

1. **Xcode compile** et extrait lui-même les textes traduisibles. C'est lui
   qui connaît les vrais emplacements de format — `%lld` pour un entier,
   `%@` pour un texte. Les deviner à la main ne se voit pas à la
   compilation, seulement à l'exécution, chez l'utilisateur.
2. `rassembler_cles.py` rassemble l'extraction en une liste lisible.
3. `completer_catalogue.py` inscrit au catalogue les textes nouveaux.
4. `traduire.py` traduit ce qui manque dans les 14 langues.
5. Le catalogue mis à jour est committé.

Rien à faire : on écrit une phrase en français dans une vue, on pousse, et
elle repart traduite partout.

## Les garde-fous

`traduire.py` refuse d'écrire une traduction qui :

- **perd ou change un emplacement de format** — `%lld` doit rester `%lld`,
  sans quoi l'affichage casse à l'exécution ;
- **change le nombre de retours à la ligne** — la mise en page dépend d'eux ;
- **mélange les alphabets** — du cyrillique dans du japonais, du hangul dans
  du chinois. C'est ce contrôle qui a rattrapé un « статистика » égaré dans
  le japonais et un « 바코드 » coréen à la place de « バーコード » ;
- **laisse un mot latin** dans une langue non latine, hors noms de marques.

Une traduction refusée n'est pas écrite, et le travail sort en erreur pour
que ça se voie. Mieux vaut un texte français visible qu'une chaîne cassée.

## Le verrou

La traduction automatique tourne à chaque poussée, mais rien n'empêcherait
de poser une étiquette de version avant qu'elle ait fini. C'est pourquoi la
**vérification de compilation** lance aussi `verifier_traductions.py` : tant
qu'un texte manque dans une langue, ou qu'une traduction a perdu un
emplacement de format, elle reste rouge. Une version ne peut pas partir
avec un écran à moitié traduit.

Le contrôle signale aussi les traductions restées identiques au français —
sans bloquer, car « Manga » ou « Honya » le sont légitimement, mais en
bloquant si toute une langue l'est, signe qu'elle n'a jamais été traduite.

## Ce qu'il faut sur le dépôt

Une clé Gemini dans les secrets GitHub, sous le nom `GEMINI_API_KEY` :
*Settings → Secrets and variables → Actions → New repository secret*.
Sans elle, le travail signale ce qui manque mais ne peut rien traduire.

## À la main, depuis Windows

    set GEMINI_API_KEY=…
    python .github/traduire.py

Les deux variables `HONYA_CATALOGUE` et `HONYA_EXTRACTION` permettent de
viser des copies pour faire des essais sans toucher au vrai catalogue.

## Retoucher une traduction

Le service fait du bon travail mais reste une machine. Pour reprendre une
formulation, on écrit la correction dans un `Design/traductions_*.py` et on
lance `python Design/catalogue.py` : les corrections à la main gagnent
toujours, et le contrôle des formats s'applique aussi à elles.
