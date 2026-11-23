# Guida per scrivere le storie di Dnd The Game

In Dnd The Game il master lo fa un modello di linguaggio piccolo che gira sul PC, senza
Internet. È bravo a descrivere, ma legge poco, ricorda poco ed è lento. Una storia scritta
tenendo conto di questi limiti gli fa dare risposte più veloci, più coerenti e con meno errori.

Questa guida raccoglie le regole da seguire quando si scrive o si prepara un'avventura nuova,
e le idee per rendere l'attesa meno pesante al tavolo.

---

## 1. Cosa legge davvero il narratore

Ogni volta che deve rispondere, il narratore riceve solo:

| Cosa | Quanto | Da dove |
|---|---|---|
| Le regole del master | Fisse | `game/story.gd`, uguali per tutto il capitolo |
| Il tono dell'avventura | Una riga, massimo 240 caratteri | Campo "Tono" della campagna |
| Il gruppo | Nome, razza, classe, livello | Schede dei personaggi |
| I mostri | Solo i nomi | Mostri della campagna e bestiario |
| La traccia del capitolo | **I primi 1400 caratteri** (circa 220 parole) | Il PDF della storia importata |
| Brani del testo completo | Al massimo 600 caratteri, solo quando servono | Paragrafi del capitolo che parlano di ciò che si è appena detto |
| La storia finora | Al massimo 250 parole | `riassunto.md`, riscritto a fine capitolo |
| Le ultime battute | 14 righe | Quello che si è detto in questo capitolo |

Tutto il resto non lo vede. Ne vengono tre regole:

1. **Le informazioni importanti di un capitolo vanno all'inizio del capitolo.** Quello che
   viene dopo i primi 1400 caratteri il narratore non lo legge.
2. **Il narratore non ricorda i dettagli dei capitoli passati**, solo il riassunto. Un PNG o un
   indizio che deve tornare va ripetuto nella traccia del capitolo in cui torna.
3. **Più è corto quello che gli si dà, più è veloce.** Le istruzioni restano le stesse per tutto
   il capitolo, così Ollama le tiene in memoria e non le rilegge.

---

## 2. Come preparare il PDF

L'app divide il PDF in capitoli usando **i titoli più grandi**. I titoli più piccoli restano
dentro il capitolo come sottotitoli.

- Un titolo grande per ogni capitolo, sempre della stessa dimensione.
- Niente titoli grandi per altro (copertina, crediti, appendici). Se ci sono, diventano capitoli
  in più.
- Intestazioni e numeri di pagina ripetuti vengono tolti da soli.
- Il PDF deve contenere testo vero, non pagine scansionate come immagini.

---

## 3. Come scrivere un capitolo

Ogni capitolo comincia con una **scheda breve** (massimo 1400 caratteri), poi può continuare
con tutto il testo che si vuole. La scheda il narratore la legge sempre. Il testo lungo non lo
legge per intero: quando un giocatore nomina un luogo, un PNG o un oggetto, l'app cerca nel
testo i paragrafi che ne parlano e glieli passa per quella sola risposta (al massimo 600
caratteri).

### Modello della scheda (in prosa, consigliato)

```
Capitolo 2: La grotta dei goblin

Obiettivo: ritrovare i mercanti rapiti della carovana.
Luoghi: l'imbocco della grotta, umido e con odore di fumo; la sala del fuoco, dove dormono
tre goblin; le gabbie in fondo, dove sono chiusi i mercanti.
PNG: Tobia, mercante anziano e spaventato, sa dove il capo goblin tiene la chiave.
Mostri: Goblin x3 nella sala del fuoco, Capo goblin vicino alle gabbie.
Prove: Furtività CD 12 per passare la sala senza svegliarli; Atletica CD 14 per forzare le gabbie.
Momenti: l'imbocco con le tracce della carovana; la sala del fuoco; le gabbie e Tobia; il capo goblin.
Il capitolo finisce quando i mercanti sono liberi e il gruppo esce dalla grotta.
```

Prova del 23/11/2026 con gli stessi scenari (`llm_bench --story`): scheda in prosa 96%, scheda
ad appunti 95%. Lo stesso risultato, ma con la prosa il narratore ha usato meglio i brani del
testo completo (2 volte su 2 contro 0 su 2): per questo la prosa resta il modo consigliato.
Gli appunti (senza articoli, con "Fine:") funzionano lo stesso, se serve spazio.

- **Momenti in ordine:** il narratore porta il gruppo dall'uno all'altro seguendo le loro scelte.
- **Dopo la scheda, il testo per esteso:** descrizioni, dialoghi, indizi, con titoletti per
  luogo o PNG. Più è scritto con i nomi che usano i giocatori, più l'app lo ritrova.

### Il testo da leggere ai giocatori

Il modo più veloce di raccontare è leggere un testo già scritto: niente attese e niente errori
del modello. I paragrafi che cominciano con **"Da leggere:"**, o che stanno sotto un titoletto
**"Da leggere"** (fino al titoletto successivo), vengono letti dalla voce all'inizio del capitolo,
uno dopo l'altro, e compaiono sullo schermo e sui telefoni.

```
Da leggere: La pioggia vi accompagna per tutta la salita. Tra i cespugli, le tracce della
carovana piegano verso una grotta da cui esce un filo di fumo.
```

- **Pausa** ferma la lettura; **Riprendi lettura** continua dal paragrafo successivo.
- Se un giocatore scrive o dice cosa fa, la lettura si ferma e risponde il narratore, che sa
  cosa è già stato letto e non lo ripete.
- **Le scelte dei giocatori cambiano il testo.** Se dall'ultimo paragrafo letto è successo
  qualcosa al tavolo (un'azione, una prova, un combattimento), prima di leggere il paragrafo
  successivo il narratore lo confronta con la situazione: lo legge così com'è, lo riscrive
  adattato (la locanda è in fiamme, non silenziosa) o lo salta (il gruppo è andato altrove).
  Se nessuno ha fatto niente, il testo viene letto parola per parola, senza attese.
- Mentre i giocatori improvvisano, il narratore conosce il prossimo paragrafo da leggere e può
  riportare la storia verso di esso, senza raccontarlo lui.
- Scrivi quindi paragrafi brevi e indipendenti: uno per scena. Un paragrafo lungo che racconta
  tre scene è più facile da sbagliare dopo una scelta inattesa.
- Un marcatore nel testo da leggere fa partire una prova o un combattimento e ferma la lettura:
  `Da leggere: Due lupi sbucano dagli alberi. [[COMBATTIMENTO: Lupo x2]]`.
- **Tutto il resto non viene letto:** scheda, segreti, note per il master restano al narratore.
  Non mettere segreti nei paragrafi "Da leggere".
- Se un capitolo non ha niente da leggere, lo apre il narratore come prima.

### Regole per la scheda

- **Obiettivo in una frase.** Il narratore lo usa per riportare il gruppo sulla strada.
- **Luoghi con un dettaglio da sentire** (odore, rumore, luce). Sono le frasi che il narratore
  riprende meglio.
- **PNG con nome, ruolo e cosa sanno.** Una sola informazione chiave per PNG.
- **Mostri con i nomi esatti** dei mostri preparati nell'app del master o del bestiario
  (`Goblin`, `Lupo`, `Capo goblin`...). Con un nome diverso il combattimento parte con un
  mostro generico.
- **Prove scritte come l'app le capisce:** abilità e CD (`Percezione CD 15`, `TS Destrezza CD 13`).
  Il narratore le copia quasi uguali.
- **Una condizione di fine capitolo chiara**, con la frase "Il capitolo finisce quando...". Senza,
  il narratore non sa quando scrivere `[[FINE CAPITOLO]]`. Nei test è il marcatore che sbaglia
  di più.
- **Niente numeri di gioco nella descrizione** (danni, PF, dadi). Li gestisce il tavolo, e il
  narratore tende a ripeterli.
- **Niente cose dette o fatte dai personaggi dei giocatori.** Il narratore le imita e poi fa agire
  i personaggi al posto dei giocatori.

### Il tono dell'avventura

Il tono si scrive una volta per tutta la campagna: nell'app del master (scheda Campagne,
sezione Storia, campo "Tono") oppure in Dnd The Game ("Impostazioni"). Il narratore lo legge
a ogni risposta, in tutti i capitoli.

- **Breve e concreto:** "Cupo, poca luce, PNG sospettosi, più dialoghi che combattimenti".
- **Niente indicazioni astratte** ("una storia epica e profonda"): il modello non sa cosa farne.
- **Niente fatti della trama:** quelli vanno nella scheda del capitolo, dove servono.

Un'indicazione che vale solo per un capitolo va nella sua scheda, per esempio
"Tono: si ride, l'oste è un buffone".

### Il controllo delle schede

Quando importi il PDF, l'app del master controlla ogni capitolo e mostra sotto la storia
cosa sistemare. Dnd The Game avvisa quando comincia un capitolo con una scheda incompleta.
I controlli, tutti sulla parte che il narratore legge (i primi 1400 caratteri):

- capitolo più lungo di 1400 caratteri senza "Obiettivo" all'inizio;
- manca "Il capitolo finisce quando...";
- dadi o sigle (`1d6`, PF, CA);
- nella riga "Mostri:" c'è un nome che non è tra i mostri preparati né nel bestiario.

Gli avvisi non bloccano niente: il capitolo si gioca lo stesso, ma il narratore sbaglia di più.

### Segreti e colpi di scena

I modelli piccoli tengono male i segreti: se la scheda dice "Tobia è il traditore", prima o poi
lo fanno capire. Scrivi il segreto come istruzione, con la condizione per rivelarlo:
"Tobia mente sulla chiave; lo ammette solo se minacciato o scoperto".

### Lunghezza dei capitoli

Un capitolo dovrebbe durare **1-2 ore di gioco**. A fine capitolo l'app scrive il riassunto e
riparte da una memoria pulita: capitoli corti tengono il narratore veloce e preciso anche nelle
campagne lunghe.

---

## 4. Come preparare i mostri

I mostri si preparano nell'app del master. I turni dei mostri li gioca l'app con regole fisse,
leggendo le note del mostro.

- Scrivi gli attacchi come `Nome +bonus, dado` (`Scimitarra +4, 1d6+2`).
- Scrivi le capacità a ricarica con `(ricarica 5-6)`: l'app tira il d6 a ogni turno.
- Scrivi i tiri salvezza come `TS Des CD 13` e l'area (`cono 4,5 m`).
- `Multiattacco: due attacchi` fa attaccare due volte.
- Nomi come "capo", "re", "regina", "drago", "non morto", "golem" fanno sì che il mostro non
  scappi mai quando è quasi morto.

---

## 5. Nomi e parole per la voce

Il racconto viene letto dalla sintesi vocale di Windows in italiano.

- **Nomi facili da pronunciare in italiano.** "Roccalta" si legge bene, "Xh'ryllth" no.
- **Niente parentesi:** la voce le salta.
- **Niente abbreviazioni** (PF, CA, CD) nelle descrizioni: la voce le legge lettera per lettera.
- **Parole d'ambiente chiare** per i luoghi: grotta, caverna, bosco, foresta, locanda, taverna,
  villaggio, città, castello, cripta, palude, montagna, mare, pioggia, tempesta, notte. Servono
  anche per scegliere i suoni d'ambiente (sezione 7).

---

## 6. Come giocare per aiutare il narratore

Da dire ai giocatori all'inizio della partita:

- **Un'azione per messaggio, con il nome del personaggio:** "Aria cerca trappole sulla porta"
  funziona meglio di "Controlliamo un po' in giro e poi forse apriamo".
- **Dite cosa fate, non cosa succede:** "Provo a scalare la parete", non "Scalo la parete e
  arrivo in cima".
- **Se più persone vogliono agire, scrivetelo in un solo messaggio** ("Aria fa la guardia, Bruno
  apre la cassa"): una risposta sola invece di due attese.
- **"Continua"** fa andare avanti la scena quando nessuno sa cosa fare.
- **"Fine capitolo"** chiude il capitolo a mano quando il narratore non se ne accorge.

---

## 7. Riempire l'attesa del narratore

Su un PC senza scheda video la prima frase arriva in circa 2-4 secondi e la risposta completa
in 10-15. Le idee qui sotto servono a non lasciare silenzi.

| Idea | Cosa fa | Effetto | Stato |
|---|---|---|---|
| Frasi di attesa | Appena un giocatore parla, la voce dice una frase breve già pronta ("Mmh, vediamo...", "Interessante.", "Il master sfoglia i suoi appunti..."), scelta a caso e adatta alla situazione (combattimento, prova appena tirata, inizio capitolo) | Copre i primi 1-2 secondi | Fatta (`FILLERS` in `game/game_main.gd`) |
| Suoni d'ambiente | Un sottofondo continuo per il luogo, che cambia quando il narratore nomina un posto nuovo e si abbassa mentre parla la voce | Il silenzio non c'è mai | Fatta (`game/ambience.gd`, casella "Ambiente") |
| Testo in diretta sui telefoni | Il racconto compare mentre viene scritto anche sui telefoni, con "il master sta pensando..." e poi "sta raccontando..." | Chi legge non sente l'attesa | Fatta |
| Dichiarazioni di gruppo | Mentre il master parla gli altri scrivono già; le azioni partono insieme in una sola richiesta | Meno attese in tutta la serata | Da fare |
| Lavoro nei momenti morti | Quando nessuno scrive, il modello legge in anticipo istruzioni e storia recente, e prepara le descrizioni dei luoghi del capitolo | Risposte più rapide; solo a modello libero | Da fare |
| Dadi | L'animazione dei dadi delle prove sui telefoni resta visibile qualche secondo | Copre l'attesa della risposta | Da fare |

### I suoni d'ambiente

Sono nove, in `web/amb/`: grotta, cripta, bosco, notte, vento, pioggia, mare, locanda, fuoco.
Il gioco sceglie il luogo dall'**ultima parola di luogo** che il narratore scrive in una risposta;
all'apertura della partita guarda l'ultima risposta salvata o, se non c'è, la scheda del capitolo.

| Suono | Parole che lo fanno partire |
|---|---|
| grotta | grotta, caverna, miniera, galleria, tunnel, cunicolo, stalattiti |
| cripta | cripta, tomba, sotterraneo, catacomba, tempio, sepolcro, mausoleo |
| bosco | bosco, boschi, foresta, alberi, radura, sentiero, sottobosco |
| locanda | locanda, taverna, osteria, bancone |
| pioggia | pioggia, piove, temporale, tempesta, acquazzone |
| notte | notte, notturno, stelle, luna |
| vento | vento, montagna, vetta, rupe, valico |
| mare | mare, spiaggia, porto, onde, nave, molo, scogli |
| fuoco | fuoco, falò, accampamento, bivacco |

Per far suonare il posto giusto, **nomina il luogo nella scheda del capitolo** con una di queste
parole. Le parole sono in `Ambience.PLACES`; i suoni si rifanno con `python tools/make_ambience.py`
(sono sintetizzati, nessun file di terzi).

Le frasi di attesa vanno scritte **senza far agire i personaggi** e senza anticipare cosa
succederà: devono andare bene sempre.

---

## 8. Scelte tecniche già fatte

- **Modello:** `gemma4:e4b-it-q4_K_M`, scelto con i test di riferimento
  (`tests/llm_results/storico.csv`): 96% dei controlli, 12,5 s a risposta su questo PC.
- **Risposte corte:** al massimo 4 frasi, chiuse da "Cosa fate?". Meno parole vuol dire meno
  attesa.
- **Ragionamento nascosto spento** (`think: false`): il modello risponde subito.
- **Modello sempre carico** per 60 minuti (`keep_alive`), memoria di 4096 token.
- **Voce in diretta:** legge frase per frase mentre il testo arriva e salta i marcatori `[[...]]`.
- **Dadi, danni, turni dei mostri e iniziativa** sono dell'app, non del modello: più veloci e
  sempre giusti.

## 9. Cose che aiutano e si fanno fuori dal programma

- **Attivare XMP (D.O.C.P.) nel BIOS:** la RAM da 3200 MHz di questo PC gira a 2666. Il modello
  è limitato dalla velocità della RAM, quindi dovrebbe guadagnare circa il 15-20%.
- **Una scheda video con almeno 8-12 GB** (per esempio una RTX 3060 da 12 GB) porterebbe la
  risposta completa a 2-3 secondi.
- **Chiudere i programmi pesanti** durante la partita.

---

## 10. Quando si cambiano le istruzioni o il modello

Ogni modifica alle regole del narratore (`game/story.gd`) o al modello va provata con i test
di riferimento, prima di giocare:

```
godot --headless --path . -s tests/llm_bench.gd
```

Il risultato finisce in `tests/llm_results/storico.csv`. Una modifica va tenuta solo se il
punteggio non scende. Le istruzioni del dettaglio sono in `tests/llm_results/LEGGIMI.md`.

---

## Promemoria veloce

- [ ] Un titolo grande per capitolo nel PDF
- [ ] Scheda in prosa di massimo 1400 caratteri all'inizio di ogni capitolo, con i momenti in ordine
- [ ] Paragrafi "Da leggere:" per l'apertura del capitolo, senza segreti
- [ ] Obiettivo, luoghi con un dettaglio, PNG con cosa sanno
- [ ] Mostri con i nomi esatti dell'app, già preparati con attacchi e note
- [ ] Prove scritte come `Abilità CD n`
- [ ] "Il capitolo finisce quando..."
- [ ] Niente numeri, parentesi o abbreviazioni nelle descrizioni
- [ ] Niente azioni o battute dei personaggi dei giocatori
- [ ] Nomi facili da leggere ad alta voce
- [ ] Capitoli da 1-2 ore di gioco
