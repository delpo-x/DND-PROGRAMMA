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

## Scaricare l'app

Gli eseguibili (Windows `.exe`, Android `.apk`) sono nelle [Releases](../../releases).

## Sviluppo

Progetto Godot 4.4.1 (GDScript). Le pagine per telefono e schermo condiviso sono in `web/` e vengono servite dall'app master sulla rete locale.

- Test: `godot --headless --path . -- --self-test out.json`, `godot --headless --path . -s tests/rules_test.gd` e `godot --headless --path . -s tests/master_new_test.gd`; pagine dei telefoni: `node tests/web_syntax.js`
- Build: `sh build.sh` (vedi i commenti nello script per la chiave di firma Android, che non è nel repository).

## Licenze

Le schede delle creature del bestiario e i testi delle regole contengono materiale del System Reference Document 5.2 di Wizards of the Coast LLC, disponibile su https://www.dndbeyond.com/srd, rilasciato con licenza [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/legalcode). I valori dell'orco vengono dal System Reference Document 5.1 (stessa licenza).
