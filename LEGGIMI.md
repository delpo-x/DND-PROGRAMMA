# L'Ultimo Disgelo — cartella per il PC di casa

Preparata il 2026-11-26 da EPIC FANTASY WRITER v1.2.0. Contiene tutto ciò che serve per giocare la prima avventura (5 giocatori, livello 5, circa 2,5 ore) con **Dnd The Game** come DM.

## Cosa c'è
| Cartella | Contenuto | Si può aprire? |
|---|---|---|
| `0-TEST-DRIVE` | `Test_Drive.json`: avventura di prova di 15 minuti con due eroi pronti e un ratto gigante, per provare l'app da soli | Sì |
| `1-APP` | `Dnd_The_Game.exe` (il PC fa il DM), `DnD_Tavolo_Master.exe` (master umano), `DnD_Tavolo_Master.apk` (tablet Android, facoltativo), `LEGGIMI-app.md` (guida completa dell'app) | Sì |
| `2-CAMPAGNA-NON-APRIRE` | `L_Ultimo_Disgelo.json`: la campagna per il narratore | **No**: contiene i segreti. Si importa senza aprirlo. |
| `3-GIOCATORI` | Presentazione della valle e guida alla creazione dei personaggi | Sì, da dare a tutti i giocatori |
| `4-SISTEMA-facoltativo` | `EPIC-FANTASY-WRITER.bundle`: tutto il progetto, per continuare a lavorarci con Claude Code | Solo per ripristinarlo: **contiene i file del DM** |

## Una volta sola, sul PC di casa
1. Copia questa cartella dove vuoi (va bene qualsiasi disco).
2. **Narratore**: installa Ollama da https://ollama.com. Poi, in un terminale, scarica il modello (serve Internet, una volta sola):
   ```
   ollama pull gemma4:e4b-it-q4_K_M
   ```
   L'app avvia Ollama da sola. Senza Ollama l'app funziona, ma la storia non la racconta nessuno.
3. Avvia `1-APP\Dnd_The_Game.exe`. Windows può mostrare un avviso di SmartScreen: l'eseguibile non è firmato.
4. **Importa la campagna senza leggerla**: scheda **Campagne** → **Importa campagna da file** → scegli `2-CAMPAGNA-NON-APRIRE\L_Ultimo_Disgelo.json`. Dopo l'importazione esci dalla scheda Campagne.

## Prima della serata
- Ognuno crea il personaggio di livello 5 seguendo `3-GIOCATORI\CREAZIONE-PERSONAGGI.md` e lo salva come scheda PDF.
- Nell'app, scheda **Giocatori** → **Importa da PDF** per ogni scheda.
- Sessione zero, 10 minuti: decidete insieme i temi da evitare e come si conoscono i personaggi.

## La serata
- PC e telefoni sulla **stessa rete Wi-Fi**. Nell'app premi **QR Giocatori**: ognuno inquadra il QR e sceglie il personaggio.
- Lo schermo del PC (o una TV) fa da schermo condiviso. Per restare all'oscuro **non aprite** la scheda Campagne, il Bestiario e le note del master.
- Il narratore impiega circa 10–15 secondi per rispondere su un PC senza scheda video.

## Dopo la serata
Il pulsante **Diario** apre la cartella con `riassunto.md` e i capitoli giocati. Riporta quella cartella al PC di lavoro: serve per aggiornare la campagna (procedura P04) prima dell'avventura successiva.

## Continuare a sviluppare a casa (facoltativo)
Con git installato, in un terminale nella cartella dove vuoi il progetto:
```
git clone EPIC-FANTASY-WRITER.bundle EPIC-FANTASY-WRITER
```
Il percorso del bundle è `4-SISTEMA-facoltativo\EPIC-FANTASY-WRITER.bundle`. Poi apri la cartella con Claude Code. Ricorda: contiene i segreti del DM, quindi prepara le avventure in una sessione che non leggi.
