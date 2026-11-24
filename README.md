# D&D Tavolo

App per giocare a Dungeons & Dragons 5e al tavolo. Il master usa l'app su PC (Windows) o tablet Android; i giocatori si collegano dal telefono con un QR code, senza installare nulla, e uno schermo condiviso può mostrare iniziativa, missioni e tiri.

Cosa fa:

- dadi 3D con suoni, tiri segreti, vantaggio e svantaggio;
- iniziativa con turni, PF, condizioni, tiri salvezza contro la morte;
- schede dei personaggi (anche importate da PDF), slot e lista incantesimi, PF temporanei, resistenze;
- bestiario con creature pronte secondo le regole 2024 (valori SRD 5.2), grado di sfida e PE;
- missioni, cronaca della campagna, salvataggi automatici con punti di ripristino ed esportazione.

Istruzioni d'uso complete in [build/LEGGIMI.md](build/LEGGIMI.md).

C'è anche **Dnd The Game**, un'app gemella in cui il master lo fa il computer: i mostri giocano con regole fisse e la storia la racconta un modello che gira sul PC con Ollama, senza Internet. Per scrivere avventure adatte al narratore locale: [GUIDA_STORIE.md](GUIDA_STORIE.md). Test del narratore: [tests/llm_results](tests/llm_results/LEGGIMI.md).

## Accessibilità (WCAG 2.2 AA)

Pagine del telefono e dello schermo condiviso:

- contrasto del testo di almeno 4.5:1 (3:1 per i titoli grandi) su tutti i pannelli, bordi dei campi di almeno 3:1;
- ogni campo, menu e casella ha un nome per i lettori di schermo; le icone decorative sono nascoste;
- pulsanti di scelta con `aria-pressed`, scheda attiva con `aria-current`, finestre con ruolo `dialog`, fuoco sul primo comando e ritorno del fuoco alla chiusura, Esc per annullare;
- avvisi, risultato dei dadi e cambio di turno annunciati (`aria-live`), stato del collegamento anche a parole;
- caselle di spunta e comandi di almeno 24×24 px, fuoco da tastiera sempre visibile, animazioni ridotte con `prefers-reduced-motion`, zoom del telefono libero.

App master e Dnd The Game: testo secondario a 4.5:1, bordi dei campi a 3:1, tutti i comandi raggiungibili con Tab e attivabili con Invio o Spazio, contorno dorato sul comando che ha il fuoco, stato dei telefoni scritto e non solo colorato.

Lettori di schermo su Windows (NVDA, JAWS, Assistente vocale), grazie a Godot 4.5:

- pulsanti, schede, caselle ed etichette vengono letti col loro testo;
- ogni campo, menu e contatore ha un nome, preso dall'etichetta accanto o dal testo d'esempio; i pulsanti fatti di un solo simbolo (X, +, −) hanno un nome a parole;
- avvisi, risultati dei tiri e righe della storia di Dnd The Game vengono annunciati senza spostare il fuoco (la narrazione quando è finita, non parola per parola).

Limiti noti: su Android Godot 4.5 non funziona ancora con TalkBack, quindi sul tablet l'app master si usa senza lettore di schermo (i giocatori usano le pagine web, che funzionano con TalkBack e VoiceOver). I dadi 3D e la mappa sono immagini: il loro contenuto è scritto anche in testo (risultato del tiro, iniziativa, registro).

## Scaricare l'app

Gli eseguibili (Windows `.exe`, Android `.apk`) sono nelle [Releases](../../releases).

## Sviluppo

Progetto Godot 4.5.2 (GDScript). Le pagine per telefono e schermo condiviso sono in `web/` e vengono servite dall'app master sulla rete locale.

- Test: `godot --headless --path . -- --self-test out.json`, `godot --headless --path . -s tests/rules_test.gd` e `godot --headless --path . -s tests/master_new_test.gd`, lettori di schermo `godot --headless --path . -s tests/a11y_test.gd`; pagine dei telefoni: `node tests/web_syntax.js`
- Build: `sh build.sh` (vedi i commenti nello script per la chiave di firma Android, che non è nel repository).

## Licenze

Le schede delle creature del bestiario e i testi delle regole contengono materiale del System Reference Document 5.2 di Wizards of the Coast LLC, disponibile su https://www.dndbeyond.com/srd, rilasciato con licenza [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/legalcode). I valori dell'orco vengono dal System Reference Document 5.1 (stessa licenza).
