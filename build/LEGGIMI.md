# D&D Tavolo Master

Un tavolo digitale per giocare a **Dungeons & Dragons 5ª edizione** in presenza, tutti nella stessa
stanza, in italiano. Non sostituisce il gioco attorno al tavolo: lo accompagna. Tira i dadi, tiene
l'ordine di iniziativa, conserva i segreti del master e mostra a tutti quello che devono vedere.

---

## 1. Obiettivi

Il programma nasce per risolvere i problemi pratici di una sessione dal vivo:

| Problema al tavolo | Cosa fa il programma |
|---|---|
| Dadi persi, tiri contestati, conti sbagliati | Dadi 3D con fisica, modificatori presi dalla scheda, totale calcolato e registrato |
| Il master deve ricordare iniziativa, PF dei mostri, round | Tracker di iniziativa con turno corrente, round, danni e cure |
| I giocatori sbirciano lo schermo del master | Ogni dispositivo riceve **solo** ciò che può vedere: i segreti non lasciano mai il master |
| Installare app su ogni telefono è scomodo | I giocatori usano il **browser**: basta inquadrare un QR code |
| Serve Internet, account, abbonamenti | Funziona **solo in rete locale (Wi-Fi)**, senza Internet né registrazioni |
| Le schede di carta si perdono | Schede salvate sul dispositivo del master, campagne e sessioni multiple |
| "Chi ha tirato cosa?" | Registro completo di tutti i tiri, filtrabile ed esportabile |

Principi che guidano tutte le scelte:

1. **Il master è l'unica fonte di verità.** Tutti i dati vivono sul suo dispositivo.
2. **Zero installazioni per i giocatori.** Un telefono qualsiasi con un browser basta.
3. **Segretezza per costruzione.** I dati nascosti non vengono filtrati "a vista" sul telefono:
   semplicemente non vengono mai inviati.
4. **Pensato per le mani e la distanza.** Pulsanti grandi per il tocco, schermo condiviso leggibile
   da lontano.
5. **Dadi che si vedono rotolare.** Il piacere del tiro resta, anche sul telefono.

---

## 2. Come è fatto: i tre ruoli

```
                 Rete Wi-Fi di casa
   ┌──────────────────────────────────────────────┐
   │                                              │
   │   TABLET / PC DEL MASTER  (unica app)        │
   │   - tutti i dati della campagna              │
   │   - server delle pagine web                  │
   │   - server in tempo reale                    │
   │        │                    │                │
   │        ▼                    ▼                │
   │   TELEFONI GIOCATORI    SCHERMO CONDIVISO    │
   │   (browser)             (browser su PC/TV)   │
   │   vista personale       vista pubblica       │
   └──────────────────────────────────────────────┘
```

### Il master (app installata)
È il cuore del sistema. L'app sul tablet Android o sul PC Windows:
- contiene campagne, personaggi, mostri, missioni e registro;
- fa da **server web**: quando un telefono apre l'indirizzo, è il tablet a fornire la pagina;
- tiene una **connessione in tempo reale** con ogni telefono e schermo, così ogni modifica arriva a
  tutti all'istante;
- decide, per ogni dispositivo, quali informazioni inviare.

### Il giocatore (pagina web sul telefono)
Il giocatore inquadra il QR, sceglie (o crea) il proprio personaggio e da quel momento ha:
dadi 3D, scheda modificabile, scorciatoie di tiro, iniziativa, missioni visibili e registro pubblico.
Il telefono non conserva dati di gioco: tiene solo un "gettone" che gli permette, se la pagina si
chiude o la batteria si scarica, di ritrovare il proprio personaggio riaprendo l'indirizzo.

### Lo schermo condiviso (pagina web su PC o TV)
Una vista "da sala": caratteri grandi, sfondo scuro, nessun comando. Mostra ordine di iniziativa,
turno corrente, gli ultimi tiri pubblici con l'animazione dei dadi e le missioni visibili.
Riceve esattamente le stesse informazioni pubbliche che vedono tutti.

### Lo spettatore (pagina web sul telefono)
Chi non gioca può seguire la partita dal proprio telefono: inquadra lo stesso QR dei giocatori e
tocca **Guarda come spettatore**. Vede le stesse cose dello schermo condiviso, impaginate per il
telefono, e non può fare nulla: niente tiri, niente PF, niente personaggio. Gli spettatori non
compaiono nell'elenco dei collegati del master. "Esci" riporta alla pagina del giocatore.

---

## 3. Regole di visibilità

La parte più importante del progetto. Il master prepara, per ogni destinatario, una **vista
filtrata** dello stato del gioco; tutto il resto resta sul tablet.

| Informazione | Master | Giocatore | Schermo |
|---|---|---|---|
| Propria scheda completa | ✔ | ✔ (solo la sua) | – |
| Schede degli altri personaggi | ✔ | nome | nome |
| CA, PF, statistiche di mostri e PNG | ✔ | ✘ – solo stato | ✘ – solo stato |
| Mostri non ancora rivelati | ✔ | ✘ | ✘ |
| Punteggi di iniziativa dei mostri | ✔ | ✘ – solo la posizione | ✘ |
| Proprio punteggio di iniziativa | ✔ | ✔ | – |
| CD delle prove | ✔ | ✘ – solo Riuscita / Fallita | ✘ |
| Missioni e prove nascoste | ✔ | ✘ | ✘ |
| Note del master | ✔ | ✘ | ✘ |
| Tiri pubblici | ✔ | ✔ | ✔ con animazione |
| Tiri segreti del master | ✔ | "Il master ha tirato in segreto" | idem |

Lo **stato** dei mostri sostituisce i PF:
- **Illeso** – punti ferita pieni
- **Ferito** – più della metà
- **Gravemente ferito** – metà o meno
- **A terra** – zero

Quando un mostro tira in pubblico, i giocatori vedono dadi e totale ma non il modificatore, così non
possono ricavarne le statistiche.

---

## 4. I dadi

- Dadi disponibili: **d4, d6, d8, d10, d12, d20, d100**. Il d100 è fatto come quello vero: un dado
  delle decine (00–90) più un d10 delle unità; 00 + 0 vale 100.
- Combinazioni libere (es. 1d20 + 2d6 + 3), **vantaggio** e **svantaggio** (due d20, si tiene il più
  alto o il più basso).
- **20 naturale** evidenziato in oro, **1 naturale** in rosso, con vibrazione sul telefono.
- Si vedono i singoli dadi e il totale.

**Sul tablet del master** i dadi usano un vero motore fisico 3D: rimbalzano sul tavolo e il
risultato è la faccia che finisce verso l'alto.

**Sul telefono e sullo schermo** i dadi sono disegnati in 3D direttamente nel browser, con una fisica
semplificata e leggera, pensata per girare fluida anche su telefoni non recenti. Per garantire
l'**equità**, il numero viene estratto con il generatore casuale sicuro del browser (ogni faccia ha
esattamente la stessa probabilità); la simulazione decide come il dado rotola e la faccia che resta
in alto mostra quel numero. Lo schermo condiviso riproduce l'animazione con gli stessi valori.

I valori della fisica (gravità, rimbalzo, attrito, forza del lancio) sono stati scelti a occhio:
si possono ritoccare se la "sensazione" non convince.

---

## 5. Il flusso di una sessione

1. **Prima della sessione** il master apre la campagna (o ne crea una), prepara mostri nel
   Bestiario e missioni con le relative prove.
2. **All'arrivo dei giocatori** il master mostra il QR; ognuno lo inquadra e sceglie il personaggio.
   Le schede restano legate al giocatore anche se si scollega.
3. **Durante l'esplorazione** il master può chiedere un tiro (es. Percezione): sul telefono del
   giocatore compare una notifica con il pulsante per tirare, il modificatore è già quello della
   scheda e la CD resta segreta. Il programma confronta totale e CD e segna l'esito della prova.
4. **In combattimento** il master avvia l'iniziativa: i mostri tirano da soli, i giocatori ricevono
   la richiesta, l'ordine si compone automaticamente. "Turno successivo" avanza il turno e il round;
   danni e cure aggiornano i PF (e lo stato visibile ai giocatori). Si possono aggiungere o togliere
   combattenti a metà scontro.
5. **Alla fine** tutto è già salvato. Il registro si può esportare in CSV (apribile con Excel).

---

## 6. Le schede del master

| Scheda | Cosa fa |
|---|---|
| **Dadi** | Dadi 3D, modificatore, vantaggio/svantaggio, interruttore Tiro pubblico / Tiro segreto, chi tira e motivo |
| **Iniziativa** | Nuovo combattimento, tiri automatici dei mostri, richiesta ai giocatori, classifica con punteggi, turno successivo, round, danni e cure |
| **Giocatori** | Telefoni collegati, schede dei personaggi, richieste di tiro in attesa |
| **Bestiario** | Mostri e PNG con CA, PF, iniziativa e note; duplicazione (Goblin 1, Goblin 2…); rivela ai giocatori |
| **Missioni** | Missioni con prove richieste (abilità + CD), nascondi/rivela, esito automatico |
| **Registro** | Tutti i tiri, anche segreti; filtri per chi, tipo e visibilità; esportazione CSV |
| **Campagne** | Più campagne e sessioni, note di sessione e di campagna, duplicazione |

## 7. Cosa trova il giocatore sul telefono

| Scheda | Cosa fa |
|---|---|
| **Dadi** | Dadi 3D, scorciatoie per abilità, tiri salvezza, attacchi e iniziativa, con il modificatore preso dalla scheda |
| **Scheda** | Caratteristiche, competenze, PF, CA, attacchi e note, modificabili |
| **Iniziativa** | Ordine dei turni, con il proprio turno evidenziato |
| **Missioni** | Solo le missioni e le prove rese visibili dal master |
| **Registro** | Tiri pubblici del gruppo |

---

## 8. Dati e salvataggi

- Tutto viene salvato automaticamente sul dispositivo del master, circa un secondo dopo ogni
  modifica. Alla riapertura si riparte dall'ultima campagna usata.
- Ogni campagna è un file a sé: si possono avere più campagne e, dentro ognuna, più sessioni.
- I telefoni non conservano nulla di importante: se un telefono si rompe, il personaggio è al sicuro
  sul tablet.
- Nessun dato esce dalla rete di casa; non ci sono account né servizi su Internet.

---

## 9. Installazione e collegamento

**Tablet Android**
1. Copia `DnD_Tavolo_Master.apk` sul tablet (cavo USB, Drive, e-mail…).
2. Aprilo e consenti "Installa app sconosciute" quando Android lo chiede.
3. Avvia **D&D Tavolo Master**.

**PC Windows**
1. Doppio clic su `DnD_Tavolo_Master.exe`.
2. Se Windows chiede il permesso per la rete, consenti l'accesso alle **reti private**.

**Collegare giocatori e schermo**
- Master, telefoni e TV devono essere sulla **stessa rete Wi-Fi**.
- Nel master premi **QR Giocatori**: i giocatori inquadrano il QR con la fotocamera
  (Safari su iPhone, Chrome su Android).
- Sul PC o sulla TV apri lo stesso indirizzo e scegli **Schermo condiviso**, poi "Schermo intero".
- Chi vuole solo guardare inquadra il QR e tocca **Guarda come spettatore**.

---

## 10. Limiti conosciuti

- Su Android l'app del master deve restare **aperta in primo piano**: se va in background il
  sistema può sospendere il collegamento con i telefoni.
- Alcune reti Wi-Fi pubbliche o aziendali impediscono ai dispositivi di vedersi tra loro: in quel
  caso usa la rete di casa o l'hotspot del tablet.
- L'app Android è stata verificata ma non ancora provata su un tablet reale.
- Aspetto grafico e "sensazione" dei dadi sono scelte iniziali, modificabili.

## 11. File in questa cartella

| File | A cosa serve |
|---|---|
| `DnD_Tavolo_Master.apk` | App del master per tablet Android |
| `DnD_Tavolo_Master.exe` | App del master per PC Windows |
| `LEGGIMI.md` | Questa guida |

## Importare da PDF

**Scheda di un personaggio.** Nella scheda *Giocatori* premi **Importa da PDF** e scegli il file. L'app legge nome, razza, classe, livello, bonus di competenza, caratteristiche, tiri salvezza, abilità, PF, CA, velocità, iniziativa e attacchi. Poi apre la scheda perché tu la controlli: quello che non trova resta al valore base. Il testo completo del PDF finisce nelle note del personaggio.

Anche un giocatore può farlo dal telefono: nella pagina di scelta del personaggio c'è **Carica scheda PDF**. Il personaggio viene creato e assegnato a quel telefono.

**Storia della campagna.** Nella scheda *Campagne*, sezione *Storia della campagna*, premi **Importa storia da PDF**. Il testo viene diviso in capitoli in base ai titoli più grandi, mentre i titoli più piccoli diventano sottotitoli. Intestazioni e numeri di pagina ripetuti vengono tolti. La storia resta visibile solo al master.

**PG pronti.** Se l'avventura elenca personaggi pronti (un nome con sotto "razza, classe", come "Kaelen / umano, guerriero"), dopo l'importazione l'app chiede se crearli. C'è anche il pulsante **Crea i PG pronti**. I personaggi che esistono già con lo stesso nome vengono saltati. Se il testo li cita con CA e PF ("Kaelen (CA 20, 84 PF...)") anche questi valori vengono usati; il resto va completato a mano o importando la loro scheda PDF.

Limiti: servono PDF con testo vero (esportati da Word, Docs, Chrome, D&D Beyond...). Le scansioni o le foto non hanno testo leggibile. I PDF protetti da password non si aprono.

## Suoni

I dadi fanno rumore (nell'app master, sul telefono e sullo schermo condiviso) quando urtano il tavolo e tra loro, più forte se l'urto è violento. Un 20 naturale, un 1 naturale e l'inizio del proprio turno hanno ciascuno un suono dedicato. I browser attivano l'audio solo dopo il primo tocco sulla pagina: se non senti nulla, tocca lo schermo una volta. Sul telefono in modalità silenziosa i suoni non si sentono, ma la vibrazione resta.

## Immagini e animazioni

I mostri del bestiario e dell'iniziativa mostrano un ritratto quando il nome contiene una di queste parole: goblin, capo goblin, coboldo, orco, scheletro, zombi, lupo, drago, bandito. Il ritratto compare nell'app master, sul telefono e sullo schermo condiviso.

Per aggiungere un ritratto a un personaggio, salva un'immagine JPG quadrata in `web/img/p/` con il nome del personaggio in minuscolo (ad esempio `aelyra.jpg`) e ricompila l'app. Per un nuovo tipo di mostro, salva l'immagine in `web/img/m/` e aggiungi la parola in `scripts/art.gd`.

Animazioni:
- quando cambia il turno compare un banner con il nome (e il ritratto) di chi deve agire;
- la riga di chi agisce ha un bagliore dorato che pulsa;
- quando qualcuno subisce danni la sua riga lampeggia di rosso e trema, di verde se viene curato;
- con un 20 naturale lo schermo si illumina d'oro e il tavolo trema, con un 1 naturale si tinge di rosso;
- sul telefono i PF pulsano quando sono sotto la metà; a 0 compare un teschio;
- sullo schermo condiviso le candele sullo sfondo tremolano.

Se il telefono è impostato per ridurre le animazioni, gli effetti in movimento vengono disattivati.

## Cronaca e salvataggi

- **Cronaca**: nuova scheda che fa da registro della campagna. Molti eventi vengono annotati in automatico: inizio sessione, combattimenti con round e nemici sconfitti, personaggi che cadono o si rialzano, mostri rivelati, missioni, critici e fallimenti critici. Puoi aggiungere voci a mano (evento, PNG, luogo, bottino, nota), correggerle o nasconderle ai giocatori. Le voci non si cancellano mai. Il pulsante "Esporta cronaca" salva tutto in un file Markdown.
- **Salvataggi sicuri**: ogni salvataggio scrive prima un file temporaneo e poi lo sostituisce, così un'interruzione non corrompe la campagna. Ogni 10 minuti, e a ogni nuova sessione, viene creato un punto di ripristino; ne vengono tenuti gli ultimi 40.
- **Scheda Campagne**: "Crea punto di ripristino", "Ripristina" su un punto precedente (prima salva comunque lo stato attuale), "Esporta campagna su file" e "Importa campagna da file" per spostarla su un altro PC.

## Dal Manuale dei Mostri

Nel Bestiario il menu "Dal Manuale dei Mostri" compila il modulo con 29 creature pronte secondo le regole 2024 (valori SRD 5.2; l'orco, che nel 2024 non ha una scheda da mostro, resta con i valori 2014): CA, PF, iniziativa, grado di sfida, PE e un promemoria degli attacchi. I PE dei mostri sconfitti finiscono nel totale del gruppo a fine combattimento.

## Regole dal Manuale del Giocatore

- **Scheda Giocatori**: pulsanti "Riposo breve" e "Riposo lungo" (il lungo riporta ai PF massimi e ridà gli slot a chi ha almeno 1 PF; a 0 PF non ha effetto) e "Assegna PE", che divide i punti esperienza in parti uguali. Ogni personaggio mostra i suoi PE.
- **Condizioni**: il menu "Condizioni" di ogni personaggio elenca le 15 condizioni del manuale (Prono, Avvelenato, Stordito...). Passando sopra una voce si legge l'effetto; quelle attive compaiono sotto il nome e sul telefono. Lo stesso menu c'è sui mostri nel Bestiario e su ogni riga dell'Iniziativa ("Cond."); le condizioni dei mostri visibili si vedono anche su telefoni e schermo.
- **Tiri salvezza contro la morte**: quando un personaggio scende a 0 PF compaiono successi e fallimenti, con i pulsanti per tirare il d20 o segnare a mano. I comandi compaiono sia nella scheda Giocatori sia nella riga del personaggio in Iniziativa. Anche il giocatore può tirarlo dal telefono: il dado lo tira il tavolo. 10 o più è un successo, 1 vale due fallimenti, 20 rimette in piedi con 1 PF.
- **Cronaca sul telefono**: nella sezione Missioni i giocatori leggono la cronaca pubblica, sessione per sessione. Lo schermo condiviso mostra gli ultimi avvenimenti.

## PF temporanei e resistenze dei mostri

- **PF temporanei**: nel Bestiario il pulsante "PF temp." dà al mostro il numero di PF temporanei scritto nella casella. Non si sommano: resta il valore più alto, come da manuale. I danni consumano prima quelli. Compaiono accanto ai PF ("+6 temp.") e si possono correggere in "Modifica".
- **Resistenze, vulnerabilità e immunità**: in "Modifica" ogni tipo di danno (acido, contundente, fuoco, veleno...) può essere Normale, Resistenza (metà), Vulnerabile (doppio) o Immune (nessun danno). I mostri pronti del Manuale le hanno già: scheletro vulnerabile al contundente, non morti immuni al veleno, draghi rossi immuni al fuoco.
- Per un mostro con difese il pulsante diventa "Danno ▾", sia nel Bestiario sia in Iniziativa: scegli il tipo di danno e il calcolo è automatico. Un avviso mostra quanti danni sono stati davvero inflitti.
- **Anche sui personaggi**: nella scheda Giocatori ogni personaggio ha "PF temp." e "Difese" (resistenze, vulnerabilità e immunità per tipo di danno). Con delle difese impostate il pulsante diventa "Danno ▾", anche in Iniziativa. Il giocatore vede le sue difese nella scheda sul telefono.

## Slot incantesimo

- Ogni personaggio incantatore mostra i suoi slot come rombi: pieno = disponibile, vuoto = usato. Toccando un rombo pieno si usa lo slot, toccando uno vuoto lo si recupera. Funziona sia nella scheda Giocatori del master sia sul telefono del giocatore (schermata Dadi).
- Il numero di slot si calcola da solo dalla classe e dal livello, con la tabella del Manuale del Giocatore: incantatori completi (bardo, chierico, druido, mago, stregone), paladino e ranger dal 2° livello, warlock con la Magia del Patto.
- Il pulsante "Slot" permette di scrivere i valori a mano (per esempio per un multiclasse) togliendo il calcolo automatico.
- Il riposo lungo ripristina tutti gli slot, quello breve solo gli slot del warlock.

## Lista incantesimi

- Ogni personaggio ha la sua lista di incantesimi: nome, livello (trucchetto o 1°-9°) e se è preparato. Il master la modifica con il pulsante "Incantesimi" nella scheda Giocatori, il giocatore dalla sua scheda sul telefono.
- Per gli incantatori l'app calcola CD del tiro salvezza e bonus di attacco (8 + competenza + modificatore della caratteristica della classe).
- Sul telefono, nella schermata Dadi, ogni incantesimo preparato è un pulsante: toccandolo si usa uno slot del suo livello, o il primo libero di livello più alto. I trucchetti non consumano slot. Se non ci sono slot liberi compare un avviso.
- Si scrivono solo i nomi: la descrizione degli incantesimi resta sul Manuale del Giocatore.

## Mappe di battaglia
Scheda **Mappa** del master.
- **Da PDF…**: sceglie il PDF dell'avventura; compaiono le immagini grandi trovate dentro (pagina e dimensioni), tocca quella della mappa. Funziona con le mappe salvate come immagine nel PDF (quasi tutte); se la mappa è disegnata a linee dal PDF stesso, fai uno screenshot e usa **Da immagine…** (PNG, JPG, WebP).
- La griglia delle caselle viene cercata da sola. Se non combacia: **Lato casella** (in pixel dell'immagine), **Inizio X / Y** per spostarla, oppure **Rileva griglia** di nuovo. **Griglia visibile** la mostra o la nasconde.
- **Pedine** (a destra): *Metti* / *Togli* per ogni personaggio e mostro, *Metti tutto il gruppo*. Si trascinano sulle caselle come a dama: una pedina per casella. Tasto destro su una pedina la toglie. Rotellina o +/− per lo zoom, trascina il vuoto per spostare la vista, *Adatta* per vederla intera.
- **Mostra ai giocatori**: la mappa va sullo schermo condiviso (al centro; i dadi compaiono sopra durante i tiri) e nella scheda *Mappa* dei telefoni. I mostri nascosti non si vedono.
- Sul telefono ogni giocatore trascina solo la propria pedina (*La mia pedina* la mette al centro, due dita per lo zoom). Il turno in corso ha l'anello giallo, chi è a 0 PF una X rossa.
- Le immagini delle mappe restano sul dispositivo del master (cartella dati dell'app, sottocartella `mappe`): l'esportazione della campagna in JSON salva griglia e pedine ma non l'immagine.
