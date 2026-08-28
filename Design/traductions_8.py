# -*- coding: utf-8 -*-
"""Traductions — vague 8 : les phrases longues des six dernières langues."""
from catalogue import ecrire

L = ("nl", "ko", "zh-Hans", "tr", "ru", "sv")


def t(*valeurs):
    return dict(zip(L, valeurs))


T = {
    # ---------------------------------------------------- chiffres et unités
    "%lld livres": t("%lld boeken", "%lld권", "%lld本书", "%lld kitap", "%lld кн.", "%lld böcker"),
    "%lld séries": t("%lld reeksen", "%lld개 시리즈", "%lld个系列", "%lld seri", "%lld сер.", "%lld serier"),
    "%lld prêtés": t("%lld uitgeleend", "%lld권 대출 중", "已借出%lld本",
                     "%lld ödünçte", "%lld одолжено", "%lld utlånade"),
    "%lld tomes · %@": t("%lld delen · %@", "%lld권 · %@", "%lld卷 · %@",
                         "%lld cilt · %@", "%lld т. · %@", "%lld delar · %@"),
    "%lld pages.": t("%lld pagina's.", "%lld쪽.", "%lld页。",
                     "%lld sayfa.", "%lld стр.", "%lld sidor."),
    "%lld min au total": t("%lld min in totaal", "총 %lld분", "共%lld分钟",
                           "toplam %lld dk", "всего %lld мин", "%lld min totalt"),
    "%lld min · %lld p.": t("%lld min · %lld p.", "%lld분 · %lld쪽", "%lld分钟 · %lld页",
                            "%lld dk · %lld s.", "%lld мин · %lld с.", "%lld min · %lld s."),
    "%lld minutes de lecture": t("%lld minuten lezen", "%lld분 독서", "阅读%lld分钟",
                                 "%lld dakika okuma", "%lld минут чтения", "%lld minuters läsning"),
    "%@ : %lld minutes": t("%@: %lld minuten", "%@: %lld분", "%@：%lld分钟",
                           "%@: %lld dakika", "%@: %lld минут", "%@: %lld minuter"),
    "%lld sur %lld débloqués": t("%lld van %lld ontgrendeld", "%lld / %lld 획득",
                                 "已获得 %lld / %lld", "%lld / %lld kazanıldı",
                                 "получено %lld из %lld", "%lld av %lld upplåsta"),
    "%lld livres reconnus": t("%lld boeken herkend", "%lld권 인식됨", "已识别%lld本",
                              "%lld kitap tanındı", "распознано %lld книг",
                              "%lld böcker igenkända"),
    "%lld trouvé%@": t("%lld gevonden%@", "%lld건%@", "找到%lld本%@",
                       "%lld bulundu%@", "найдено %lld%@", "%lld hittade%@"),
    "p. %lld sur %lld": t("p. %lld van %lld", "%lld / %lld쪽", "第%lld页，共%lld页",
                          "s. %lld / %lld", "с. %lld из %lld", "s. %lld av %lld"),
    "p. %lld sur %lld · %lld %%": t(
        "p. %lld van %lld · %lld %%", "%lld / %lld쪽 · %lld %%",
        "第%lld页，共%lld页 · %lld %%", "s. %lld / %lld · %lld %%",
        "с. %lld из %lld · %lld %%", "s. %lld av %lld · %lld %%"),
    "Pages lues : %lld": t("Gelezen pagina's: %lld", "읽은 페이지: %lld", "已读页数：%lld",
                           "Okunan sayfa: %lld", "Прочитано страниц: %lld",
                           "Lästa sidor: %lld"),
    "sur %lld %@": t("van %lld %@", "%lld %@ 중", "共%lld %@",
                     "%lld %@ içinde", "из %lld %@", "av %lld %@"),
    "sur %lld lectures": t("van %lld boeken", "%lld권 중", "共%lld本",
                           "%lld okumadan", "из %lld книг", "av %lld böcker"),
    "sur %lld min · aujourd'hui": t("van %lld min · vandaag", "%lld분 중 · 오늘",
                                    "共%lld分钟 · 今天", "%lld dk içinde · bugün",
                                    "из %lld мин · сегодня", "av %lld min · i dag"),
    "sur votre objectif de %lld minutes": t(
        "van je doel van %lld minuten", "목표 %lld분 중", "目标%lld分钟中",
        "%lld dakikalık hedefinden", "из вашей цели в %lld минут",
        "av ditt mål på %lld minuter"),
    "Objectif du jour : %lld minutes sur %lld": t(
        "Doel van vandaag: %lld van %lld minuten", "오늘의 목표: %lld / %lld분",
        "今日目标：%lld / %lld分钟", "Bugünün hedefi: %lld / %lld dakika",
        "Цель дня: %lld из %lld минут", "Dagens mål: %lld av %lld minuter"),
    "objectif du jour atteint ✦": t(
        "doel van vandaag gehaald ✦", "오늘의 목표 달성 ✦", "已达成今日目标 ✦",
        "bugünün hedefi tamam ✦", "цель дня достигнута ✦", "dagens mål uppnått ✦"),
    "objectif du jour atteint dans %lld min": t(
        "doel van vandaag over %lld min", "%lld분 뒤 오늘의 목표 달성",
        "再%lld分钟达成今日目标", "%lld dk sonra bugünün hedefi",
        "цель дня через %lld мин", "dagens mål om %lld min"),
    "%lld minutes lues aujourd'hui — lancer une session": t(
        "%lld minuten gelezen vandaag — start een sessie",
        "오늘 %lld분 읽었습니다 — 세션 시작", "今天已读%lld分钟 — 开始一次阅读",
        "Bugün %lld dakika okundu — bir oturum başlat",
        "Сегодня прочитано %lld минут — начать сеанс",
        "%lld minuter lästa i dag — starta ett pass"),
    "en avance de %lld": t("%lld voor", "%lld권 앞서감", "领先%lld本",
                           "%lld önde", "на %lld впереди", "%lld före"),
    "en retard de %lld": t("%lld achter", "%lld권 뒤처짐", "落后%lld本",
                           "%lld geride", "на %lld отстаёте", "%lld efter"),
    "Défi %@": t("Uitdaging %@", "%@ 챌린지", "%@挑战", "%@ meydan okuması",
                 "Вызов %@", "Utmaning %@"),
    "Rétrospective %@": t("Terugblik %@", "%@ 돌아보기", "%@回顾",
                          "%@ geriye bakış", "Итоги %@", "Året %@ i backspegeln"),
    "Tome %lld —": t("Deel %lld —", "%lld권 —", "第%lld卷 —",
                     "%lld. cilt —", "Том %lld —", "Del %lld —"),
    "Reprendre · p. %lld": t("Hervat · p. %lld", "이어 읽기 · %lld쪽", "继续 · 第%lld页",
                             "Sürdür · s. %lld", "Продолжить · с. %lld", "Återuppta · s. %lld"),
    "Lu jusqu'au chapitre %lld": t(
        "Gelezen tot hoofdstuk %lld", "%lld화까지 읽음", "已读到第%lld话",
        "%lld. bölüme kadar okundu", "Прочитано до главы %lld", "Läst till kapitel %lld"),
    "Lu le %@.": t("Gelezen op %@.", "%@에 읽음.", "%@读完。",
                   "%@ tarihinde okundu.", "Прочитано %@.", "Läst den %@."),
    "Commencé le": t("Begonnen op", "시작일", "开始于", "Başlangıç", "Начато", "Påbörjad"),
    "Terminé le": t("Uitgelezen op", "완독일", "读完于", "Bitiş", "Завершено", "Avslutad"),
    "Prochain à acheter : tome %lld": t(
        "Volgende te kopen: deel %lld", "다음에 살 책: %lld권", "下一本要买：第%lld卷",
        "Alınacak sonraki: %lld. cilt", "Следующий к покупке: том %lld",
        "Nästa att köpa: del %lld"),
    "Recherche de %lld ISBN…": t(
        "%lld ISBN's opzoeken…", "ISBN %lld건 검색 중…", "正在查找%lld个 ISBN…",
        "%lld ISBN aranıyor…", "Поиск %lld ISBN…", "Söker %lld ISBN…"),
    "La connexion a échoué (erreur %lld).": t(
        "Verbinding mislukt (fout %lld).", "연결에 실패했습니다 (오류 %lld).",
        "连接失败（错误 %lld）。", "Bağlantı başarısız (hata %lld).",
        "Не удалось подключиться (ошибка %lld).", "Anslutningen misslyckades (fel %lld)."),
    "Plus de livres de : %@": t(
        "Meer boeken van %@", "%@의 다른 책", "%@的更多作品",
        "%@ yazarından daha fazla", "Ещё книги: %@", "Fler böcker av %@"),
    "Les tomes 1 à %lld seront marqués comme lus — et donc possédés.": t(
        "Deel 1 tot %lld worden als gelezen gemarkeerd — en dus als in bezit.",
        "1권부터 %lld권까지 읽음(따라서 소장)으로 표시합니다.",
        "第1卷至第%lld卷将标为已读，因此也算已拥有。",
        "1. ciltten %lld. cilde kadar okundu — dolayısıyla rafta — sayılacak.",
        "Тома с 1 по %lld будут отмечены прочитанными — и значит, имеющимися.",
        "Del 1 till %lld markeras som lästa — och därmed som ägda."),
    "Les tomes 1 à %lld seront marqués comme possédés. Les suivants passent en manquants.": t(
        "Deel 1 tot %lld komen in de kast. De rest wordt als ontbrekend gemarkeerd.",
        "1권부터 %lld권까지 소장으로 표시하고, 이후는 미소장이 됩니다.",
        "第1卷至第%lld卷标为已拥有，其余标为缺少。",
        "1. ciltten %lld. cilde kadar rafta sayılacak. Sonrakiler eksik olacak.",
        "Тома с 1 по %lld будут отмечены имеющимися. Остальные — недостающими.",
        "Del 1 till %lld hamnar i hyllan. Resten markeras som saknade."),

    # --------------------------------------------------------------- badges
    "2 h de lecture d'affilée": t(
        "2 uur achter elkaar lezen", "2시간 연속 독서", "连续阅读2小时",
        "Arka arkaya 2 saat okuma", "2 часа чтения подряд", "2 timmars läsning i sträck"),
    "10 sessions après minuit": t(
        "10 sessies na middernacht", "자정 이후 10회 독서", "午夜后阅读10次",
        "Gece yarısından sonra 10 oturum", "10 сеансов после полуночи",
        "10 pass efter midnatt"),
    "5 genres dans le même mois": t(
        "5 genres in één maand", "한 달에 5개 장르", "同一个月读5种类型",
        "Aynı ay içinde 5 tür", "5 жанров за один месяц", "5 genrer samma månad"),
    "5 tomes en un week-end": t(
        "5 delen in één weekend", "주말에 5권", "一个周末读5卷",
        "Bir hafta sonunda 5 cilt", "5 томов за выходные", "5 delar på en helg"),
    "50 livres non lus possédés": t(
        "50 ongelezen boeken in de kast", "읽지 않은 책 50권 소장",
        "拥有50本未读书", "Rafta 50 okunmamış kitap",
        "50 непрочитанных книг в наличии", "50 olästa böcker i hyllan"),
    "Lire avant 7 h, 5 fois": t(
        "5 keer voor 7 uur lezen", "아침 7시 전에 5번 읽기", "早上7点前阅读5次",
        "Sabah 7'den önce 5 kez okuma", "Читать до 7 утра, 5 раз",
        "Läsa före kl. 7, 5 gånger"),
    "Série de 30 jours": t("30 dagen op rij", "30일 연속", "连续30天",
                           "30 günlük seri", "Серия в 30 дней", "30 dagar i rad"),
    "Une série finie à 100 %": t(
        "Een reeks voor 100 % uit", "시리즈 100 % 완독", "系列100 %读完",
        "Bir seriyi 100 % bitirmek", "Серия завершена на 100 %",
        "En serie klar till 100 %"),

    # --------------------------------------------------------------- écrans
    "Ajoutez des envies depuis la recherche.": t(
        "Voeg vanuit Zoeken toe wat je wilt hebben.",
        "검색에서 갖고 싶은 책을 추가하세요.", "从搜索里添加你想要的书。",
        "İstediklerini aramadan ekle.", "Добавляйте желаемое из поиска.",
        "Lägg till det du vill ha från Sök."),
    "Ajoutez des livres ou des séries depuis la recherche.": t(
        "Voeg boeken of reeksen toe vanuit Zoeken.",
        "검색에서 책이나 시리즈를 추가하세요.", "从搜索里添加图书或系列。",
        "Aramadan kitap veya seri ekle.", "Добавляйте книги или серии из поиска.",
        "Lägg till böcker eller serier från Sök."),
    "Aucun tome pour l'instant — ajoutez-les avec le bouton ci-dessus.": t(
        "Nog geen delen — voeg ze toe met de knop hierboven.",
        "아직 권이 없습니다 — 위 버튼으로 추가하세요.",
        "还没有卷 — 用上方按钮添加。",
        "Henüz cilt yok — yukarıdaki düğmeyle ekle.",
        "Томов пока нет — добавьте их кнопкой выше.",
        "Inga delar än — lägg till dem med knappen ovan."),
    "Ces étagères se remplissent toutes seules d'après vos statuts, vos notes et vos dates d'achat.": t(
        "Deze planken vullen zichzelf op basis van je statussen, beoordelingen en aankoopdata.",
        "이 책장들은 상태·평점·구매일을 바탕으로 저절로 채워집니다.",
        "这些书架会依据你的状态、评分和购买日期自动填充。",
        "Bu raflar durumlarına, puanlarına ve satın alma tarihlerine göre kendiliğinden dolar.",
        "Эти полки заполняются сами — по вашим статусам, оценкам и датам покупки.",
        "De här hyllorna fyller sig själva utifrån dina statusar, betyg och inköpsdatum."),
    "Créez une étagère ici avec « + », puis rangez-y un livre ou une série depuis sa fiche (menu « … ») ou par un appui long dans la bibliothèque.": t(
        "Maak hier een plank met ‘+’ en zet er dan een boek of reeks op vanaf de detailpagina (menu ‘…’) of met lang indrukken in de bibliotheek.",
        "‘+’로 여기에 책장을 만들고, 작품 페이지의 ‘…’ 메뉴나 서재에서 길게 누르기로 책이나 시리즈를 넣으세요.",
        "用「+」在这里新建书架，然后从作品页的「…」菜单或在书库长按，把书或系列放进去。",
        "Burada ‘+’ ile bir raf oluştur, sonra kitabın sayfasından (‘…’ menüsü) ya da kitaplıkta uzun basarak içine bir kitap veya seri koy.",
        "Создайте здесь полку кнопкой «+», затем поставьте на неё книгу или серию со страницы книги (меню «…») или долгим нажатием в библиотеке.",
        "Skapa en hylla här med ”+” och ställ sedan en bok eller serie där från dess sida (menyn ”…”) eller med ett långt tryck i biblioteket."),
    "« %@ » y sera rangé aussitôt.": t(
        "‘%@’ gaat er meteen op.", "「%@」이(가) 바로 들어갑니다.",
        "「%@」会立刻放进去。", "“%@” hemen oraya gidecek.",
        "«%@» сразу окажется там.", "”%@” hamnar där direkt."),
    "Ce que racontent vos étagères": t(
        "Wat je planken vertellen", "책장이 말해 주는 것", "书架讲述的你",
        "Rafların ne anlatıyor", "Что говорят ваши полки", "Vad dina hyllor berättar"),
    "Compté tout seul depuis vos étagères": t(
        "Rechtstreeks van je planken geteld", "책장에서 자동으로 계산됩니다",
        "直接从你的书架统计", "Doğrudan raflarından sayıldı",
        "Подсчитано прямо с ваших полок", "Räknat direkt från dina hyllor"),
    "Vos lectures terminées, mois par mois": t(
        "Je uitgelezen boeken, maand na maand", "다 읽은 책, 달마다",
        "读完的书，按月排列", "Bitirdiğin okumalar, ay ay",
        "Ваши дочитанные книги, месяц за месяцем", "Dina utlästa böcker, månad för månad"),
    "Les genres apparaîtront avec vos premiers ajouts.": t(
        "Genres verschijnen zodra je je eerste boeken toevoegt.",
        "첫 책을 추가하면 장르가 나타납니다.", "添加第一批书后就会显示类型。",
        "İlk kitaplarını ekleyince türler görünür.",
        "Жанры появятся с первыми добавленными книгами.",
        "Genrer dyker upp när du lägger till dina första böcker."),
    "Lancez une session depuis l'accueil : minutes, pages et records se mesurent tout seuls.": t(
        "Start een sessie vanaf Vandaag: minuten, pagina's en records meten zichzelf.",
        "‘오늘’에서 세션을 시작하면 분·페이지·기록이 저절로 측정됩니다.",
        "从「今天」开始一次阅读：分钟、页数和纪录都会自动统计。",
        "Bugün ekranından bir oturum başlat: dakikalar, sayfalar ve rekorlar kendiliğinden ölçülür.",
        "Начните сеанс с экрана «Сегодня»: минуты, страницы и рекорды считаются сами.",
        "Starta ett pass från I dag: minuter, sidor och rekord mäts av sig själva."),
    "Votre année de lecture en cartes partageables — rendez-vous en décembre.": t(
        "Je leesjaar in deelbare kaarten — tot in december.",
        "한 해의 독서를 공유 카드로 — 12월에 만나요.",
        "把一年的阅读做成可分享的卡片 — 十二月见。",
        "Okuma yılın paylaşılabilir kartlarda — aralıkta görüşürüz.",
        "Ваш читательский год в карточках, которыми можно поделиться, — до декабря.",
        "Ditt läsår som delbara kort — vi ses i december."),
    "Un joker par semaine protège votre série de lecture : une soirée ratée ne brûle pas 40 jours d'effort.": t(
        "Eén joker per week beschermt je reeks: één gemiste avond verbrandt geen 40 dagen inspanning.",
        "주에 한 번의 면제가 연속 기록을 지켜 줍니다. 하루 걸렀다고 40일의 노력이 사라지지는 않습니다.",
        "每周一次的豁免会保护你的连续记录：错过一晚，不会烧掉40天的努力。",
        "Haftada bir joker serini korur: kaçan bir akşam 40 günlük emeği yakmaz.",
        "Один джокер в неделю бережёт вашу серию: пропущенный вечер не сжигает 40 дней усилий.",
        "En joker i veckan skyddar din rad: en missad kväll bränner inte 40 dagars möda."),
    "Modifiable à tout moment dans les réglages. Un joker par semaine protège votre série.": t(
        "Altijd te wijzigen in Instellingen. Eén joker per week beschermt je reeks.",
        "설정에서 언제든 바꿀 수 있습니다. 주에 한 번의 면제가 기록을 지켜 줍니다.",
        "随时可在设置中修改。每周一次的豁免会保护你的连续记录。",
        "Ayarlardan istediğin zaman değiştirilebilir. Haftada bir joker serini korur.",
        "Можно изменить в любой момент в настройках. Один джокер в неделю бережёт серию.",
        "Kan ändras när som helst i Inställningar. En joker i veckan skyddar din rad."),
    "Comme dans Apple Books : quelques minutes par jour suffisent à construire une série.": t(
        "Net als in Apple Books: een paar minuten per dag zijn genoeg voor een reeks.",
        "Apple 도서처럼, 하루 몇 분이면 기록이 이어집니다.",
        "就像 Apple 图书：每天几分钟就能连成记录。",
        "Apple Kitaplar'daki gibi: günde birkaç dakika bir seri kurmaya yeter.",
        "Как в Apple Books: нескольких минут в день достаточно, чтобы выстроить серию.",
        "Precis som i Apple Böcker: några minuter om dagen räcker för en rad."),
    "Lisez chaque jour : la série grandit et les statistiques suivent.": t(
        "Lees elke dag: de reeks groeit en de cijfers volgen.",
        "매일 읽으면 기록이 늘고 통계도 따라옵니다.",
        "每天阅读：记录会增长，统计也跟上。",
        "Her gün oku: seri büyür, istatistikler onu izler.",
        "Читайте каждый день: серия растёт, а статистика следует за ней.",
        "Läs varje dag: raden växer och statistiken följer med."),
    "La première langue est la principale : la recherche la privilégie et les titres s'affichent dans leur version officielle publiée dans cette langue — jamais de traduction automatique.": t(
        "De eerste taal is de hoofdtaal: het zoeken geeft er voorrang aan en titels verschijnen in hun officieel uitgegeven vorm — nooit machinaal vertaald.",
        "첫 번째 언어가 주 언어입니다. 검색이 그 언어를 우선하고, 제목은 그 언어로 정식 출간된 표기로 표시됩니다(기계 번역은 쓰지 않습니다).",
        "第一种语言是主语言：搜索会优先使用它，书名按该语言的正式出版名显示，绝不使用机器翻译。",
        "İlk dil ana dildir: arama onu öne çıkarır ve başlıklar o dilde resmen yayımlanmış hâliyle görünür — asla makine çevirisiyle değil.",
        "Первый язык — основной: поиск отдаёт ему предпочтение, а названия показываются в официально изданном виде на этом языке, без машинного перевода.",
        "Det första språket är huvudspråket: sökningen prioriterar det och titlar visas i sin officiellt utgivna form — aldrig maskinöversatta."),
    "La recherche privilégie les éditions dans vos langues, et les titres s'affichent tels qu'ils sont officiellement publiés.": t(
        "Het zoeken geeft voorrang aan uitgaven in jouw talen, en titels verschijnen precies zoals ze zijn uitgegeven.",
        "검색은 당신의 언어로 된 판을 우선하며, 제목은 정식 출간된 그대로 표시됩니다.",
        "搜索优先使用你所选语言的版本，书名按正式出版的样子显示。",
        "Arama, senin dillerindeki baskıları öne çıkarır ve başlıklar yayımlandıkları hâliyle görünür.",
        "Поиск отдаёт предпочтение изданиям на ваших языках, а названия показываются так, как они изданы.",
        "Sökningen prioriterar utgåvor på dina språk, och titlar visas precis som de getts ut."),
    "La synchronisation iCloud (CloudKit) arrive dans une prochaine version — vos données restent à vous.": t(
        "iCloud-synchronisatie (CloudKit) komt in een volgende versie — je gegevens blijven van jou.",
        "iCloud 동기화(CloudKit)는 다음 버전에서 지원합니다. 데이터는 당신의 것입니다.",
        "iCloud 同步（CloudKit）将在后续版本推出 — 你的数据始终属于你。",
        "iCloud eşitlemesi (CloudKit) sonraki bir sürümde gelecek — verilerin senin kalır.",
        "Синхронизация с iCloud (CloudKit) появится в следующей версии — ваши данные остаются вашими.",
        "iCloud-synk (CloudKit) kommer i en kommande version — dina data förblir dina."),
    "Métadonnées : Google Books, Open Library, AniList. Les couvertures restent la propriété de leurs éditeurs.": t(
        "Metagegevens: Google Books, Open Library, AniList. Covers blijven eigendom van hun uitgevers.",
        "메타데이터: Google Books, Open Library, AniList. 표지의 권리는 각 출판사에 있습니다.",
        "元数据：Google Books、Open Library、AniList。封面版权归各出版社所有。",
        "Üstveri: Google Books, Open Library, AniList. Kapaklar yayıncılarının mülkiyetinde kalır.",
        "Метаданные: Google Books, Open Library, AniList. Обложки остаются собственностью издателей.",
        "Metadata: Google Books, Open Library, AniList. Omslagen tillhör respektive förlag."),
    "Effacer toute la bibliothèque, les sessions et les badges ? Cette action est définitive.": t(
        "De hele bibliotheek, sessies en badges wissen? Dit kan niet ongedaan worden gemaakt.",
        "서재·세션·배지를 모두 지울까요? 되돌릴 수 없습니다.",
        "清除整个书库、阅读记录和徽章？此操作无法撤销。",
        "Tüm kitaplık, oturumlar ve rozetler silinsin mi? Bu geri alınamaz.",
        "Стереть всю библиотеку, сеансы и значки? Это необратимо.",
        "Radera hela biblioteket, passen och märkena? Det går inte att ångra."),
    "Le code-barres au dos du livre suffit : titre, couverture et pages arrivent tout seuls, tome après tome.": t(
        "De streepjescode achterop volstaat: titel, cover en pagina's komen vanzelf, deel na deel.",
        "책 뒤의 바코드만 있으면 됩니다. 제목·표지·쪽수가 한 권씩 저절로 채워집니다.",
        "书背面的条码就够了：书名、封面和页数会一卷接一卷自动到位。",
        "Kitabın arkasındaki barkod yeter: başlık, kapak ve sayfa sayısı cilt cilt kendiliğinden gelir.",
        "Достаточно штрихкода на обороте: название, обложка и страницы придут сами, том за томом.",
        "Streckkoden på baksidan räcker: titel, omslag och sidor kommer av sig själva, del efter del."),
    "Saisissez l'ISBN à la main (13 chiffres, sous le code-barres).": t(
        "Typ de ISBN met de hand (13 cijfers, onder de streepjescode).",
        "ISBN을 직접 입력하세요(바코드 아래 13자리).",
        "手动输入 ISBN（条码下方13位数字）。",
        "ISBN'i elle gir (barkodun altında 13 hane).",
        "Введите ISBN вручную (13 цифр под штрихкодом).",
        "Skriv in ISBN för hand (13 siffror, under streckkoden)."),
    "Scannez toute une étagère": t(
        "Scan een hele plank", "책장을 통째로 스캔", "扫描整排书架",
        "Bütün bir rafı tara", "Отсканируйте целую полку", "Skanna en hel hylla"),
    "Scannez un ISBN ou cherchez un titre pour poser votre premier livre sur l'étagère.": t(
        "Scan een ISBN of zoek een titel om je eerste boek op de plank te zetten.",
        "ISBN을 스캔하거나 제목을 검색해 첫 책을 책장에 올려 보세요.",
        "扫描 ISBN 或搜索书名，把第一本书放上书架。",
        "İlk kitabını rafa koymak için bir ISBN tara ya da bir başlık ara.",
        "Отсканируйте ISBN или найдите название, чтобы поставить первую книгу на полку.",
        "Skanna en ISBN eller sök en titel för att ställa din första bok i hyllan."),
    "Les livres reconnus apparaîtront ici, prêts à rejoindre la bibliothèque.": t(
        "Herkende boeken verschijnen hier, klaar voor je bibliotheek.",
        "인식된 책이 여기에 나타나 서재에 담을 수 있습니다.",
        "识别到的书会出现在这里，随时可加入书库。",
        "Tanınan kitaplar burada belirir, kitaplığa girmeye hazır.",
        "Распознанные книги появятся здесь, готовые попасть в библиотеку.",
        "Igenkända böcker dyker upp här, redo för biblioteket."),
    "Visez le code-barres au dos du livre": t(
        "Richt op de streepjescode achterop het boek", "책 뒤의 바코드를 비춰 주세요",
        "对准书背面的条码", "Kitabın arkasındaki barkodu hedefle",
        "Наведите на штрихкод на обороте книги", "Rikta mot streckkoden på bokens baksida"),
    "L'écran reste allumé pendant la session.": t(
        "Het scherm blijft aan tijdens de sessie.", "세션 중에는 화면이 꺼지지 않습니다.",
        "阅读期间屏幕保持常亮。", "Oturum boyunca ekran açık kalır.",
        "Во время сеанса экран не гаснет.", "Skärmen förblir tänd under passet."),
    "L'humeur de cette session (optionnel)": t(
        "De stemming van deze sessie (optioneel)", "이번 독서의 기분 (선택)",
        "这次阅读的心情（可选）", "Bu oturumun havası (isteğe bağlı)",
        "Настроение этого сеанса (необязательно)", "Stämningen i det här passet (valfritt)"),
    "Abandonner cette session ?": t(
        "Deze sessie weggooien?", "이 세션을 버릴까요?", "放弃这次阅读记录？",
        "Bu oturum atılsın mı?", "Отменить этот сеанс?", "Kasta det här passet?"),
    "Abandonner sans enregistrer": t(
        "Weggooien zonder bewaren", "저장하지 않고 버리기", "不保存直接放弃",
        "Kaydetmeden at", "Отменить без сохранения", "Kasta utan att spara"),
    "Gardez ici les phrases qui vous ont arrêté.": t(
        "Bewaar hier de zinnen waarbij je bleef hangen.",
        "마음이 멈춘 문장을 여기에 남기세요.", "把让你停下来的句子留在这里。",
        "Seni durduran cümleleri burada sakla.",
        "Сохраняйте здесь фразы, на которых вы остановились.",
        "Spara här de meningar som fick dig att stanna upp."),
    "Recopiez la citation…": t(
        "Schrijf het citaat over…", "인용을 옮겨 적으세요…", "抄下这段话…",
        "Alıntıyı buraya yaz…", "Перепишите цитату…", "Skriv av citatet…"),
    "Prêter ce livre": t("Leen dit boek uit", "이 책 빌려주기", "借出这本书",
                         "Bu kitabı ödünç ver", "Одолжить эту книгу", "Låna ut den här boken"),
    "Retirer « %@ » de la bibliothèque ?": t(
        "‘%@’ uit je bibliotheek halen?", "「%@」을(를) 서재에서 제거할까요?",
        "从书库移除「%@」？", "“%@” kitaplıktan kaldırılsın mı?",
        "Убрать «%@» из библиотеки?", "Ta bort ”%@” från biblioteket?"),
    "Retirer « %@ » et tous ses tomes ?": t(
        "‘%@’ met alle delen weghalen?", "「%@」과(와) 모든 권을 제거할까요?",
        "移除「%@」及其所有卷？", "“%@” ve tüm ciltleri kaldırılsın mı?",
        "Убрать «%@» и все её тома?", "Ta bort ”%@” och alla dess delar?"),
    "Supprimer votre compte et toutes vos données ?": t(
        "Je account en al je gegevens verwijderen?", "계정과 모든 데이터를 삭제할까요?",
        "删除你的账户和所有数据？", "Hesabın ve tüm verilerin silinsin mi?",
        "Удалить учётную запись и все данные?", "Radera ditt konto och alla dina data?"),
    "Votre bibliothèque, vos sessions, vos badges et vos étagères seront effacés. C'est sans retour.": t(
        "Je bibliotheek, sessies, badges en planken worden gewist. Zonder weg terug.",
        "서재·세션·배지·책장이 모두 지워집니다. 되돌릴 수 없습니다.",
        "你的书库、阅读记录、徽章和书架都会被清除，无法恢复。",
        "Kitaplığın, oturumların, rozetlerin ve rafların silinecek. Geri dönüşü yok.",
        "Ваша библиотека, сеансы, значки и полки будут стёрты. Без возврата.",
        "Ditt bibliotek, dina pass, märken och hyllor raderas. Ingen väg tillbaka."),
    "Supprimer votre compte efface aussi toute votre bibliothèque sur cet appareil. Pour retirer Honya de votre identifiant Apple, allez dans Réglages > votre nom > Connexion avec Apple.": t(
        "Je account verwijderen wist ook je hele bibliotheek op dit apparaat. Om Honya van je Apple-account los te koppelen: Instellingen > je naam > Log in met Apple.",
        "계정을 삭제하면 이 기기의 서재도 모두 지워집니다. Apple 계정에서 Honya를 해제하려면 설정 > 사용자 이름 > Apple로 로그인 으로 가세요.",
        "删除账户也会清除本机上的整个书库。要从 Apple 账户中移除 Honya，请前往 设置 > 你的姓名 > 通过 Apple 登录。",
        "Hesabını silmek bu cihazdaki tüm kitaplığını da siler. Honya'yı Apple hesabından kaldırmak için Ayarlar > adın > Apple ile Giriş Yap yolunu izle.",
        "Удаление учётной записи также стирает всю библиотеку на этом устройстве. Чтобы отвязать Honya от Apple ID: Настройки > ваше имя > Вход с Apple.",
        "Att radera ditt konto raderar även hela biblioteket på den här enheten. För att koppla bort Honya från ditt Apple-konto: Inställningar > ditt namn > Logga in med Apple."),
    "Vos lectures restent sur votre appareil. Vous pouvez supprimer votre compte à tout moment depuis les réglages.": t(
        "Je leesgegevens blijven op je apparaat. Je kunt je account altijd verwijderen in Instellingen.",
        "독서 기록은 기기에 남습니다. 계정은 설정에서 언제든 삭제할 수 있습니다.",
        "你的阅读记录留在设备上。你可以随时在设置中删除账户。",
        "Okumaların cihazında kalır. Hesabını istediğin zaman Ayarlar'dan silebilirsin.",
        "Ваши записи о чтении остаются на устройстве. Учётную запись можно удалить в любой момент в настройках.",
        "Din läsning stannar på din enhet. Du kan radera ditt konto när som helst i Inställningar."),
    "Rien n'est partagé, et votre compte s'efface d'un bouton.": t(
        "Er wordt niets gedeeld, en je account is met één knop weg.",
        "아무것도 공유되지 않으며, 계정은 버튼 하나로 사라집니다.",
        "什么都不会被分享，账户一键即可删除。",
        "Hiçbir şey paylaşılmaz ve hesabın tek düğmeyle silinir.",
        "Ничего не передаётся, а учётная запись удаляется одной кнопкой.",
        "Inget delas, och ditt konto försvinner med en knapptryckning."),
    "Vos lectures vous appartiennent": t(
        "Je leesgegevens zijn van jou", "독서는 당신의 것입니다", "阅读属于你自己",
        "Okumaların sana ait", "Ваше чтение принадлежит вам", "Din läsning är din"),
    "Tous vos tomes, à jour": t(
        "Al je delen, bijgewerkt", "모든 권을 최신 상태로", "所有卷，始终最新",
        "Tüm ciltlerin, güncel", "Все ваши тома — в актуальном виде",
        "Alla dina delar, uppdaterade"),
    "Ajoutez un tome, la série entière apparaît — dates de sortie comprises.": t(
        "Voeg één deel toe en de hele reeks verschijnt — inclusief verschijningsdata.",
        "한 권만 추가하면 시리즈 전체가, 발매일까지 함께 나타납니다.",
        "只要添加一卷，整个系列就会出现 — 连发行日期也一并带上。",
        "Bir cilt ekle, tüm seri belirir — çıkış tarihleriyle birlikte.",
        "Добавьте один том — появится вся серия, вместе с датами выхода.",
        "Lägg till en del så dyker hela serien upp — utgivningsdatum inkluderade."),
    "Dans votre langue": t("In jouw taal", "당신의 언어로", "以你的语言",
                           "Kendi dilinde", "На вашем языке", "På ditt språk"),
    "Titres, couvertures et résumés dans l'édition de votre pays.": t(
        "Titels, covers en samenvattingen uit de uitgave van jouw land.",
        "당신 나라의 판으로 된 제목·표지·줄거리.",
        "书名、封面和简介，均取自你所在国家的版本。",
        "Ülkenin baskısındaki başlıklar, kapaklar ve özetler.",
        "Названия, обложки и аннотации из издания вашей страны.",
        "Titlar, omslag och sammanfattningar från ditt lands utgåva."),
    "Excellentes lectures à zéro euro": t(
        "Uitstekende boeken voor niets", "0원으로 읽는 좋은 책",
        "零元也能读到的好书", "Sıfır liraya harika okumalar",
        "Отличные книги бесплатно", "Utmärkta läsupplevelser för noll kronor"),
    "Les incontournables du moment": t(
        "Wat iedereen nu leest", "지금 놓칠 수 없는 책", "此刻不容错过",
        "Şu anın kaçırılmazları", "То, что все сейчас читают", "Det alla läser just nu"),
    "Les livres que vous comptez ouvrir bientôt.": t(
        "De boeken die je binnenkort wilt opslaan.", "곧 펼치려는 책들.",
        "你打算很快翻开的书。", "Yakında açmayı düşündüğün kitaplar.",
        "Книги, которые вы собираетесь скоро открыть.",
        "Böckerna du tänker öppna snart."),
    "Les prochains tomes de vos séries.": t(
        "De volgende delen van je reeksen.", "당신이 따라가는 시리즈의 다음 권.",
        "你在追的系列的下一卷。", "Takip ettiğin serilerin sonraki ciltleri.",
        "Следующие тома ваших серий.", "Nästa delar i dina serier."),
    "Le libraire installe l'étal…": t(
        "De boekhandelaar richt de tafel in…", "서점 직원이 매대를 차리는 중…",
        "书店店员正在摆台…", "Kitapçı tezgâhı kuruyor…",
        "Книготорговец раскладывает витрину…", "Bokhandlaren dukar upp bordet…"),
    "Un petit objectif\nchaque jour": t(
        "Elke dag\neen klein doel", "매일\n작은 목표 하나", "每天\n一个小目标",
        "Her gün\nküçük bir hedef", "Небольшая цель\nкаждый день",
        "Ett litet mål\nvarje dag"),
    "Vos langues\nde lecture": t(
        "Jouw\nleestalen", "읽는\n언어", "你的\n阅读语言",
        "Okuma\ndillerin", "Ваши языки\nчтения", "Dina\nlässpråk"),
    "Votre bibliothèque, vivante.\nQue lisez-vous ?": t(
        "Je bibliotheek, levend.\nWat lees je?", "살아 있는 서재.\n무엇을 읽고 있나요?",
        "让书库活起来。\n你在读什么？", "Kitaplığın, canlı.\nNe okuyorsun?",
        "Ваша библиотека — живая.\nЧто вы читаете?", "Ditt bibliotek, levande.\nVad läser du?"),
    "« Système » suit le réglage de votre iPhone.": t(
        "‘Systeem’ volgt de instelling van je iPhone.",
        "‘시스템 설정’은 iPhone의 설정을 따릅니다.",
        "「跟随系统」会依照 iPhone 的设置。",
        "“Sistem”, iPhone'unun ayarını izler.",
        "«Как в системе» следует настройке вашего iPhone.",
        "”System” följer inställningen på din iPhone."),
    "Ajuster l'objectif": t("Doel aanpassen", "목표 조정", "调整目标",
                            "Hedefi ayarla", "Настроить цель", "Justera målet"),
    "Tout « À lire »": t("Alles ‘Te lezen’", "「읽을 책」 전체", "全部「待读」",
                         "Tümü “Okunacak”", "Всё «К прочтению»", "Allt ”Att läsa”"),
    "De l'éditeur": t("Van de uitgever", "출판사 소개", "出版社简介",
                      "Yayıncıdan", "От издателя", "Från förlaget"),
    "De l’éditeur": t("Van de uitgever", "출판사 소개", "出版社简介",
                      "Yayıncıdan", "От издателя", "Från förlaget"),
    "Content de vous revoir.": t(
        "Fijn je weer te zien.", "다시 만나서 반갑습니다.", "很高兴又见到你。",
        "Seni yeniden görmek güzel.", "Рады видеть вас снова.", "Kul att se dig igen."),
    "Créez votre compte avec une adresse e-mail.": t(
        "Maak je account met een e-mailadres.", "이메일 주소로 계정을 만드세요.",
        "用电子邮件地址创建账户。", "Hesabını bir e-posta adresiyle oluştur.",
        "Создайте учётную запись с адресом эл. почты.",
        "Skapa ditt konto med en e-postadress."),
    "Compte créé. Ouvrez le courrier de confirmation, puis connectez-vous.": t(
        "Account aangemaakt. Open de bevestigingsmail en log dan in.",
        "계정을 만들었습니다. 확인 메일을 연 뒤 로그인하세요.",
        "账户已创建。请打开确认邮件，然后登录。",
        "Hesap oluşturuldu. Doğrulama e-postasını aç, sonra giriş yap.",
        "Учётная запись создана. Откройте письмо-подтверждение и войдите.",
        "Kontot är skapat. Öppna bekräftelsemejlet och logga sedan in."),
    "Adresse e-mail ou mot de passe incorrect.": t(
        "Onjuist e-mailadres of wachtwoord.", "이메일 주소 또는 비밀번호가 올바르지 않습니다.",
        "电子邮件地址或密码不正确。", "E-posta adresi veya şifre hatalı.",
        "Неверный адрес эл. почты или пароль.", "Fel e-postadress eller lösenord."),
    "Un compte existe déjà avec cette adresse. Connectez-vous.": t(
        "Er bestaat al een account met dit adres. Log in.",
        "이 주소의 계정이 이미 있습니다. 로그인하세요.",
        "该地址已有账户，请登录。",
        "Bu adresle bir hesap zaten var. Giriş yap.",
        "Учётная запись с этим адресом уже есть. Войдите.",
        "Det finns redan ett konto med den adressen. Logga in."),
    "Le mot de passe doit faire au moins 6 caractères.": t(
        "Het wachtwoord moet minstens 6 tekens hebben.", "비밀번호는 6자 이상이어야 합니다.",
        "密码至少需要6个字符。", "Şifre en az 6 karakter olmalı.",
        "Пароль должен содержать не менее 6 символов.",
        "Lösenordet måste vara minst 6 tecken."),
    "Cette adresse e-mail ne semble pas valide.": t(
        "Dit e-mailadres lijkt niet geldig.", "이 이메일 주소는 올바르지 않아 보입니다.",
        "这个电子邮件地址似乎无效。", "Bu e-posta adresi geçerli görünmüyor.",
        "Этот адрес эл. почты выглядит недействительным.",
        "Den här e-postadressen ser inte giltig ut."),
    "Confirmez d'abord votre adresse : un courrier vous attend.": t(
        "Bevestig eerst je adres: er wacht een e-mail op je.",
        "먼저 주소를 확인해 주세요. 메일이 도착해 있습니다.",
        "请先确认你的地址：有一封邮件在等你。",
        "Önce adresini doğrula: seni bir e-posta bekliyor.",
        "Сначала подтвердите адрес: вас ждёт письмо.",
        "Bekräfta din adress först: ett mejl väntar på dig."),
    "Trop de tentatives. Réessayez dans quelques minutes.": t(
        "Te veel pogingen. Probeer het over een paar minuten opnieuw.",
        "시도가 너무 많습니다. 몇 분 뒤에 다시 시도하세요.",
        "尝试次数过多，请几分钟后再试。",
        "Çok fazla deneme. Birkaç dakika sonra tekrar dene.",
        "Слишком много попыток. Повторите через несколько минут.",
        "För många försök. Försök igen om några minuter."),
    "Réponse inattendue du serveur.": t(
        "Onverwacht antwoord van de server.", "서버에서 예기치 않은 응답이 왔습니다.",
        "服务器返回了意外的响应。", "Sunucudan beklenmeyen yanıt.",
        "Неожиданный ответ сервера.", "Oväntat svar från servern."),
    "Les comptes par adresse e-mail ne sont pas encore configurés dans cette version.": t(
        "E-mailaccounts zijn in deze versie nog niet ingesteld.",
        "이 버전에서는 이메일 계정을 아직 쓸 수 없습니다.",
        "此版本尚未启用电子邮件账户。",
        "E-posta hesapları bu sürümde henüz yapılandırılmadı.",
        "Учётные записи по эл. почте в этой версии ещё не настроены.",
        "E-postkonton är ännu inte uppsatta i den här versionen."),
}

if __name__ == "__main__":
    ecrire(T)
