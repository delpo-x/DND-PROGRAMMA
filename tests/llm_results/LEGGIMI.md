# Test di riferimento del narratore locale

Qui finiscono i risultati di `tests/llm_bench.gd`, che mette alla prova il narratore di
Dnd The Game (il modello che gira sul PC con Ollama) sempre con le stesse situazioni di gioco.
Servono per capire se un cambio di modello o delle istruzioni del master migliora o peggiora.

## Come si lancia

Ollama deve essere installato, con il modello scaricato. Dalla cartella `app`:

```
godot --headless --path . -s tests/llm_bench.gd
godot --headless --path . -s tests/llm_bench.gd -- --model qwen2.5:3b
godot --headless --path . -s tests/llm_bench.gd -- --runs 3 --only combattimento
```

- `--model`: il modello da provare (di base quello delle impostazioni, `qwen2.5:7b`).
- `--runs`: quante volte ripetere ogni scenario (di base 2). Il modello non risponde mai due
  volte uguale, quindi più ripetizioni danno un punteggio più affidabile.
- `--only`: solo gli scenari che contengono questa parola. Questi giri non finiscono nello storico.

Su un PC senza scheda video un giro completo dura circa 10 minuti.

## Gli scenari

| Scenario | Cosa deve fare il narratore |
|---|---|
| apertura | Presentare la scena iniziale, senza marcatori |
| esplorazione | Descrivere la grotta (prova facoltativa) |
| prova_percezione | Chiedere una prova a chi cerca trappole |
| prova_atletica | Chiedere una prova a chi si arrampica |
| combattimento | Far partire il combattimento quando un personaggio attacca |
| imboscata | Far partire il combattimento quando i mostri attaccano |
| dialogo | Far parlare il PNG, senza marcatori |
| dopo_combattimento | Raccontare la fine dello scontro senza numeri |
| fine_capitolo | Chiudere il capitolo quando la missione è compiuta |
| riassunto | Riassumere il capitolo in poche parole, con i fatti principali |

## I controlli

Ogni risposta viene controllata con regole semplici, sempre uguali:

- arriva una risposta;
- è in italiano (nessuna parola inglese comune);
- non contiene dadi né numeri di gioco (`1d6`, `5 danni`, `9 PF`): quelli li gestisce il tavolo;
- è corta: al massimo 5 frasi e 90 parole, perché viene letta ad alta voce;
- finisce con una domanda ai giocatori;
- nessuna frase comincia con un personaggio dei giocatori che agisce ("Aria apre la porta");
- i marcatori `[[...]]` stanno alla fine;
- c'è il marcatore giusto: `[[PROVA]]` scritto bene, `[[COMBATTIMENTO]]` con mostri esistenti,
  `[[FINE CAPITOLO]]`, oppure nessuno.

Il controllo sui personaggi è severo: segna anche quando il narratore ripete l'azione appena
scritta dal giocatore ("Aria esamina la porta"). Le istruzioni lo vietano, quindi conta come errore.

## I file

- `AAAA-MM-GG_modello.md`: tutte le risposte del giro, con i controlli superati e mancati.
  Un nuovo giro nello stesso giorno con lo stesso modello sovrascrive il file.
- `storico.csv`: una riga per ogni giro completo: data, modello, versione delle istruzioni
  (cambia da sola quando cambia il prompt), punteggio, tempo alla prima parola, tempo della
  risposta completa, token al secondo.
