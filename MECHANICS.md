# D&D Tavolo – valori che determinano il funzionamento

Fonti: **richiesta** = la descrizione scritta dalla persona; **5e** = regole base di D&D 5ª edizione
(SRD); **2024** = regole 2024 del Manuale del Giocatore, scelte per il tavolo; **stimato** = scelto da me, nessuna prova disponibile (clean room, nessuna immagine di riferimento).

## Rete
| Valore | Dato | Fonte |
|---|---|---|
| Porta pagine web (HTTP) | 8080 (se occupata: 8090, 8180, 8280, 8380) | stimato |
| Porta tempo reale (WebSocket) | porta HTTP + 1 (8081) | stimato |
| Indirizzi | /giocatore, /schermo, / (scelta) | richiesta |
| Riconnessione automatica del browser | ogni 1,5 s; ping ogni 15 s | stimato |
| Rientro del giocatore | token salvato nel browser → stesso personaggio | richiesta |
| Righe di registro inviate ai giocatori | ultime 40 | stimato |
| Righe di registro conservate sul master | 5000 | stimato |
| Salvataggio automatico | 1 s dopo ogni modifica | stimato |
| QR code | byte mode, correzione M, versioni 1–10 | stimato |

## Dadi
| Valore | Dato | Fonte |
|---|---|---|
| Tipi | d4, d6, d8, d10, d12, d20, d100 (= dado delle decine 00–90 + d10 0–9; 00+0 = 100) | richiesta / 5e |
| Vantaggio / svantaggio | 2d20, tiene il più alto / il più basso | 5e |
| 20 e 1 naturali | solo se resta un solo d20 tenuto; effetto oro / rosso, vibrazione | richiesta |
| Danni da critico (telefono) | numero di dadi raddoppiato | 5e |
| d4 | si legge il vertice in alto | 5e (dado reale) |
| Senza dadi scelti | LANCIA tira 1d20 | stimato |

### Fisica nel browser (telefono e schermo condiviso)
| Valore | Dato | Fonte |
|---|---|---|
| Gravità | 75 unità/s² (dado ≈ 1 unità) | stimato |
| Passo di simulazione | 1/120 s, mostrato a 60 fps | stimato |
| Rimbalzo pavimento / sponde | 0,32 / 0,5 | stimato |
| Attrito | 0,45 | stimato |
| Smorzamento lineare / rotazione | 0,15 / 0,5 al secondo | stimato |
| Lancio | 9–15 unità/s in avanti, rotazione 14–24 rad/s | stimato |
| Durata massima | 6 s (frenata extra dopo 3,5 s) | stimato |
| Equità | valore estratto con generatore casuale uniforme (crypto), la fisica decide come rotola; la faccia in alto riceve quel numero | stimato |
| Grandezza tavolo | altezza 5,5–8 unità (5 sullo schermo condiviso) | stimato |

### Fisica sul tablet del master (Godot)
| Valore | Dato | Fonte |
|---|---|---|
| Tavolo | 16 × 10 unità, sponde alte 1 | stimato |
| Gravità | 9,8 × 2,6 | stimato |
| Rimbalzo / attrito dado | 0,32 / 0,55 | stimato |
| Smorzamento lineare / rotazione | 0,15 / 0,8 | stimato |
| Lancio | 13–19 unità/s, rotazione 14–24 rad/s | stimato |
| Fine tiro | dadi fermi per 0,35 s; dado in bilico spinto (max 4 volte); limite 8 s | stimato |
| Risultato | faccia con la normale più verso l'alto (fisica reale) | richiesta |

## Regole
| Valore | Dato | Fonte |
|---|---|---|
| Modificatore caratteristica | (punteggio − 10) / 2 per difetto | 5e |
| Abilità | mod. caratteristica + competenza × (0, 1 o 2 per maestria) | 5e |
| Tiro salvezza | mod. caratteristica + competenza se competente | 5e |
| Iniziativa | d20 + mod. Destrezza + bonus extra | 5e |
| Ordine di iniziativa | punteggio ↓; a pari punteggio ordine casuale (estratto una volta per combattente, poi resta fisso) | richiesta |
| Esito prova | totale ≥ CD = riuscita (il 20 naturale non vince da solo) | 5e |
| Prova con più giocatori | riuscita se almeno uno riesce, fallita quando tutti hanno fallito | stimato |
| Stato mostro per i giocatori | Illeso (PF pieni), Ferito (> metà), Gravemente ferito (≤ metà), A terra (0) | richiesta |
| PF temporanei | assorbono il danno per primi | 5e |
| Danni a 0 PF (personaggi) | un fallimento al tiro contro la morte e fine dello stato stabile (il critico vale due: lo segna il master) | 2024 |
| Morte sul colpo | danni rimasti dopo lo 0 ≥ PF massimi | 2024 |
| Personaggio morto | non si cura finché il master non azzera i tiri contro la morte | stimato |
| Riposo lungo | PF e slot pieni solo con almeno 1 PF; a 0 PF nessun effetto | 2024 |
| Slot di paladino e ranger | dal 1° livello (2 slot), poi tabella degli incantatori completi a metà livello | 2024 |
| Condizioni | testi del glossario 2024 | 2024 |
| PF dal telefono | i pulsanti −/+ del giocatore passano dalle stesse regole dei pulsanti del master | richiesta |
| Duplicato | "Goblin" → "Goblin 1", copie "Goblin 2", "Goblin 3"… con PF pieni | richiesta |
| Tiro di iniziativa automatico dei mostri | d20 + mod., registrato come tiro segreto | richiesta |

## Visibilità (cosa arriva ai browser)
- Mostri/PNG: solo quelli rivelati, solo nome + stato generico (niente CA, PF, iniziativa, note).
- Iniziativa: solo nomi e turno; il proprio punteggio è visibile, gli altri no; i mostri nascosti non compaiono.
- Prove: mai la CD; l'esito compare solo se la missione e la prova non sono nascoste.
- Tiri segreti del master: "Il master ha tirato in segreto", senza dadi; nessuna animazione inviata.
- Tiri pubblici dei mostri: dadi e totale, modificatore nascosto; nome del mostro solo se rivelato.
- Missioni e prove nascoste e note del master: mai inviate.
