# python tools/make_monster_manual.py
# Generates scripts/monster_manual.gd from the summaries of the
# dnd5e-monster-manual skill: name, CR, type and a short play note. AC, HP,
# initiative and attacks are estimated from the CR with a simple formula.
from fractions import Fraction

T = {"A": "Aberrazione", "B": "Bestia", "C": "Celestiale", "K": "Costrutto", "D": "Drago", "E": "Elementale",
     "F": "Folletto", "I": "Immondo", "G": "Gigante", "U": "Umanoide", "M": "Mostruosità", "O": "Melma",
     "P": "Vegetale", "N": "Non morto"}

ROWS = r"""
Aarakocra|1/4|U|Uomini-uccello, volano veloci e attaccano in picchiata
Aboleth|10|A|Leggendario, tana acquatica. Affascina con la mente 3 volte al giorno, tentacoli che portano una malattia della pelle
Deva|10|C|Angelo: armi magiche radianti, cura, vista del vero
Planetar|16|C|Angelo: armi magiche radianti, cura, vista del vero
Solar|21|C|Angelo leggendario; il suo arco uccide all'istante chi resta con 100 PF o meno
Animated Armor|1|K|Inerme in un campo antimagico o dopo dissolvi magie; sembra un'armatura qualsiasi
Flying Sword|1/4|K|Inerme in un campo antimagico; sembra una spada qualsiasi
Rug of Smothering|2|K|Sembra un tappeto; soffoca chi trattiene
Ankheg|2|M|Scava sotto terra, sente le vibrazioni, spruzzo di acido (ricarica 6)
Azer|2|E|Nani di fuoco: il loro calore brucia chi li tocca
Banshee|4|N|Lamento (1 al giorno): chi fallisce il TS scende a 0 PF. Volto orrendo che spaventa e invecchia
Basilisk|3|M|Sguardo pietrificante; chi distoglie lo sguardo evita il TS ma attacca con svantaggio
Behir|11|M|Fulmine in linea, inghiotte, si arrampica. Nemico dei draghi
Beholder|13|A|Leggendario. 10 raggi oculari, cono antimagico dall'occhio centrale; vola e sfrutta la tana
Death Tyrant|14|N|Beholder non morto, i raggi creano zombie
Spectator|3|A|Guardiano evocato della stirpe dei beholder, 4 raggi
Gauth|6|A|Parente minore del beholder, si nutre di magia
Gazer|1/2|A|Piccolo occhio fluttuante, raggi deboli
Twig Blight|1/8|P|Pianta maligna, arriva in branco
Needle Blight|1/4|P|Pianta maligna che lancia aghi, arriva in branco
Vine Blight|1/2|P|Pianta maligna che intralcia con i rampicanti
Bugbear Chief|3|U|Capo bugbear: colpi brutali, +2d6 contro bersagli sorpresi. Imboscate
Bulette|5|M|Squalo di terra: scava e salta schiacciando chi sta sotto
Bullywug|1/4|U|Uomini-rana, mimetismo di palude, salto da fermi
Cambion|5|I|Figlio di un immondo e di un umanoide: vola, incantesimi innati, ammalia
Carrion Crawler|2|M|Tentacoli che avvelenano e paralizzano
Centaur|2|M|Carica, arco lungo, nomadi della natura
Chimera|6|M|Tre teste (leone, capra, drago), soffio di fuoco (ricarica 5-6)
Chuul|4|A|Chele che afferrano, tentacoli paralizzanti; servitori degli aboleth
Cloaker|8|A|Sembra un mantello, si avvolge sulla testa della vittima; illusioni e lamento
Cockatrice|1/2|M|Il morso pietrifica a poco a poco (TS su Cos)
Couatl|4|C|Serpente piumato benevolo, cambia forma, protegge e cura
Crawling Claw|0|N|Mano mozzata animata, arriva a sciami
Cyclops|6|G|Vede male le distanze: svantaggio agli attacchi a distanza oltre 9 m
Darkmantle|1/2|M|Si lascia cadere dal soffitto e crea oscurità magica
Death Knight|17|N|Paladino caduto: sfera di fuoco infernale, para i colpi, comanda non morti
Demilich|18|N|Teschio fluttuante leggendario: ululato, prosciuga la vita, imprigiona le anime nelle gemme
Allosaurus|2|B|Predatore veloce, balzo e morso
Ankylosaurus|3|B|Corazzato, coda a mazza
Pteranodon|1/4|B|Rettile volante, attacca in volo
Plesiosaurus|2|B|Rettile marino, morso lungo
Triceratops|5|B|Carica con le corna
Tyrannosaurus Rex|8|B|Morso che afferra, coda
Displacer Beast|3|M|Immagine spostata: gli attacchi contro di lui hanno svantaggio finché non viene colpito
Doppelganger|3|M|Cambia forma, legge i pensieri superficiali, attacca di sorpresa
Dracolich|17|N|Drago non morto (base drago blu adulto) con un ricettacolo, resiste alla magia
Shadow Dragon|13|D|Drago trasformato dalla Coltre Oscura (base drago rosso giovane), soffio necrotico
Dragon Turtle|17|D|Gigantesca tartaruga marina, soffio di vapore
Drider|6|M|Drow trasformato in ragno da Lolth: si arrampica, incantesimi
Dryad|1|F|Legata al suo albero, ammalia, passa da un albero all'altro
Duergar|1|U|Nani grigi: si ingrandiscono e diventano invisibili, sensibili alla luce del sole
Manes|1/8|I|Demone minore, carne da cannone a orde
Dretch|1/4|I|Demone minore, nube fetida, a orde
Quasit|1|I|Demone famiglio, invisibile, cambia forma
Shadow Demon|4|I|Demone incorporeo, forte nell'oscurità
Barlgura|5|I|Demone bruto saltatore
Chasme|6|I|Demone insetto, il ronzio fa svenire
Vrock|6|I|Demone avvoltoio: spore e grido stordente
Hezrou|8|I|Demone rospo: fetore che avvelena
Glabrezu|9|I|Demone che esaudisce desideri ingannevoli; chele, incantesimi
Nalfeshnee|13|I|Demone con aura di orrore, si teletrasporta
Marilith|16|I|Demone a sei braccia, molti attacchi, para i colpi
Goristro|17|I|Demone gigante, carica devastante, abbatte le strutture
Balor|19|I|Demone: frusta di fuoco, aura di fiamme, esplode quando muore
Lemure|0|I|Diavolo informe, rigenera se non ucciso con armi benedette
Imp|1|I|Diavolo famiglio, invisibile, cambia forma
Spined Devil|2|I|Diavolo volante che lancia aculei
Bearded Devil|3|I|Diavolo con barba avvelenata
Barbed Devil|5|I|Diavolo coperto di spine, lancia fiamme
Chain Devil|8|I|Diavolo che anima le catene
Bone Devil|9|I|Diavolo con pungiglione velenoso
Horned Devil|11|I|Diavolo con tridente e coda infernale
Erinyes|12|I|Diavola alata con arco e corda che intralcia
Ice Devil|14|I|Diavolo del freddo, muro di ghiaccio
Pit Fiend|20|I|Diavolo supremo: aura di paura, morso velenoso, palla di fuoco a volontà
Faerie Dragon (young)|1|D|Draghetto fatato, invisibile, soffio euforico
Faerie Dragon (old)|2|D|Draghetto fatato, invisibile, soffio euforico
Pseudodragon|1/4|D|Famiglio telepatico, pungiglione che addormenta
Wyvern|6|D|Pungiglione velenoso, niente soffio
Air Elemental|5|E|Turbine che solleva e scaglia
Earth Elemental|5|E|Attraversa la roccia
Fire Elemental|5|E|Incendia ciò che tocca
Water Elemental|5|E|Sommerge e trattiene
Drow|1/4|U|Elfi del Sottosuolo: sangue fatato, sensibili alla luce del sole, veleno, incantesimi innati
Drow Elite Warrior|5|U|Guerriero drow scelto, veleno, sensibile alla luce del sole
Drow Mage|7|U|Incantatore drow, sensibile alla luce del sole
Drow Priestess of Lolth|8|U|Sacerdotessa drow, sensibile alla luce del sole
Empyrean|23|C|Figlio di una divinità, leggendario
Ettercap|2|M|Ragnatele, ragni giganti al seguito
Ettin|4|G|Due teste: una resta sempre sveglia
Flameskull|4|N|Teschio volante, incantesimi da mago, rinasce se non viene benedetto
Flumph|1/8|A|Gentile e telepatico, informatore utile
Fomorian|8|G|Gigante deforme del Sottosuolo, malocchio
Shrieker|0|P|Fungo che strilla e dà l'allarme
Violet Fungus|1/4|P|Fungo con tocco che fa marcire
Gas Spore|1/2|P|Esplode spargendo spore di beholder
Galeb Duhr|6|E|Masso vivente, anima le rocce
Gargoyle|2|E|Sembra una statua finché non si muove
Dao|11|E|Genio della terra
Djinni|11|E|Genio dell'aria; se nobile concede desideri
Efreeti|11|E|Genio del fuoco
Marid|11|E|Genio dell'acqua
Ghost|4|N|Possessione, passa nel Piano Etereo, volto orrendo
Ghast|2|N|Artigli paralizzanti (gli elfi sono immuni), fetore
Hill Giant|5|G|Il più basso dell'Ordinamento dei giganti, lancia massi
Stone Giant|7|G|Lancia massi
Frost Giant|8|G|Lancia massi, terre gelate
Fire Giant|9|G|Lancia massi, fabbri delle fucine
Cloud Giant|9|G|Lancia massi, castelli sulle nuvole
Storm Giant|13|G|Il più alto dell'Ordinamento, fulmini
Gibbering Mouther|2|A|Il balbettio confonde, rende il terreno difficile
Githyanki Warrior|3|U|Guerriero astrale con spada d'argento, nemico dei mind flayer
Githyanki Knight|8|U|Cavaliere astrale con spada d'argento, nemico dei mind flayer
Githzerai Monk|2|U|Monaco psionico del Limbo
Githzerai Zerth|6|U|Maestro psionico del Limbo
Gnoll Pack Lord|2|U|Dopo aver ridotto qualcuno a 0 PF si muove e attacca come azione bonus
Fang of Yeenoghu|4|I|Gnoll prediletto del demone, furia dopo ogni uccisione
Deep Gnome|1/2|U|Svirfneblin: si mimetizza nelle rocce
Flesh Golem|5|K|Forma immutabile, resiste alla magia; il fulmine lo rinforza
Clay Golem|9|K|Forma immutabile, resiste alla magia; l'acido lo cura
Stone Golem|10|K|Forma immutabile, resiste alla magia, rallenta
Iron Golem|16|K|Forma immutabile, resiste alla magia; il fuoco lo cura, soffio velenoso
Gorgon|5|M|Toro di ferro, soffio pietrificante
Green Hag|3|F|Illusioni, patti e scambi; tre megere formano una congrega
Sea Hag|2|F|Volto orrendo, patti; tre megere formano una congrega
Night Hag|5|I|Incubi, viaggia nei sogni; tre megere formano una congrega
Harpy|1|M|Canto che affascina e attira
Hell Hound|3|I|Soffio di fuoco, tattica di branco
Helmed Horror|4|K|Armatura animata, immune a 3 incantesimi scelti
Hippogriff|1|M|Cavalcatura volante
Hobgoblin Captain|3|U|+2d6 con un alleato vicino al bersaglio, disciplina militare
Hobgoblin Warlord|6|U|+2d6 con un alleato vicino al bersaglio, comanda le truppe
Homunculus|0|K|Servitore del mago, morso che addormenta
Hook Horror|3|M|Ganci, si orienta con l'eco nei cunicoli
Hydra|8|M|Più teste: una tagliata ne fa ricrescere due, salvo con il fuoco
Intellect Devourer|2|A|Divora il cervello e prende il controllo del corpo
Invisible Stalker|6|E|Sempre invisibile, cacciatore evocato
Jackalwere|1/2|U|Sciacallo mannaro, sguardo che addormenta
Kenku|1/4|U|Imitano solo i suoni che hanno sentito
Winged Kobold|1/4|U|Coboldo alato, lancia sassi dall'alto, tattica di branco
Kraken|23|M|Leggendario: tentacoli, fulmini, inghiotte
Kuo-toa|1/4|U|Pazzi del Sottosuolo, creano dèi con la fede
Kuo-toa Whip|1|U|Sacerdote kuo-toa
Kuo-toa Archpriest|6|U|Gran sacerdote kuo-toa
Lamia|4|M|Tocco che offusca la Saggezza, illusioni
Lich|21|N|Leggendario, incantatore di 18° livello, filatterio, tocco paralizzante
Lizardfolk|1/2|U|Pratici e spietati, trattengono il respiro
Lizardfolk Shaman|2|U|Sciamano degli uomini lucertola
Lizard King/Queen|4|U|Sovrano degli uomini lucertola
Werebear|5|U|Mannaro: immune alle armi non magiche e non argentate, il morso trasmette la maledizione
Wereboar|4|U|Mannaro: immune alle armi non magiche e non argentate, il morso trasmette la maledizione
Wererat|2|U|Mannaro: immune alle armi non magiche e non argentate, il morso trasmette la maledizione
Weretiger|4|U|Mannaro: immune alle armi non magiche e non argentate, il morso trasmette la maledizione
Werewolf|3|U|Mannaro: immune alle armi non magiche e non argentate, il morso trasmette la maledizione
Magmin|1/2|E|Esplode in fiamme quando muore
Manticore|3|M|Lancia a distanza le spine della coda
Medusa|6|M|Sguardo pietrificante, capelli di serpenti, arco
Dust Mephit|1/2|E|Soffio accecante, esplode quando muore
Ice Mephit|1/2|E|Soffio gelido, esplode quando muore
Magma Mephit|1/2|E|Soffio di fuoco, esplode quando muore
Mud Mephit|1/4|E|Soffio di fango, esplode quando muore
Smoke Mephit|1/4|E|Soffio di cenere, esplode quando muore
Steam Mephit|1/4|E|Soffio di vapore, esplode quando muore
Merfolk|1/8|U|Popolo del mare
Merrow|2|M|Merfolk corrotti da Demogorgon
Mind Flayer|7|A|Onda psichica a cono che stordisce, tentacoli, estrae il cervello e uccide all'istante
Minotaur|3|M|Carica, non si perde mai nei labirinti
Monodrone|1/8|K|Modron di Mechanus, ordine assoluto
Duodrone|1/4|K|Modron di Mechanus, ordine assoluto
Tridrone|1/2|K|Modron di Mechanus, ordine assoluto
Quadrone|1|K|Modron di Mechanus, ordine assoluto
Pentadrone|2|K|Modron di Mechanus, ordine assoluto
Mummy|3|N|Putrefazione della mummia (maledizione), vulnerabile al fuoco
Mummy Lord|15|N|Leggendario, putrefazione della mummia, vulnerabile al fuoco
Myconid Sprout|0|P|Comunica con le spore, pacifico
Myconid Adult|1/2|P|Comunica con le spore, pacifico
Myconid Sovereign|2|P|Comunica con le spore, anima i cadaveri
Bone Naga|4|N|Serpente con volto umano, incantatore
Spirit Naga|8|M|Serpente con volto umano, incantatore, rinasce
Guardian Naga|10|M|Serpente con volto umano, incantatore, rinasce
Nightmare|3|I|Cavalcatura infernale, viaggia nel Piano Etereo
Nothic|2|A|Sguardo che fa marcire, scopre i segreti
Half-Ogre|1|G|Brutale e affamato
Oni|7|G|Cambia forma, si rigenera, incantesimi innati
Black Pudding|4|O|Corrode armi e armature, si divide se colpito da fulmini o tagli
Gray Ooze|1/2|O|Corrode il metallo
Ochre Jelly|2|O|Si divide se colpita da fulmini o tagli
Orc War Chief|4|U|Si lancia verso il nemico come azione bonus, comanda gli orchi
Eye of Gruumsh|2|U|Sacerdote orco, si lancia verso il nemico come azione bonus
Orog|2|U|Orco scelto, si lancia verso il nemico come azione bonus
Otyugh|5|A|Vive nei rifiuti, morso con malattia, telepatia
Pegasus|2|C|Cavalcatura volante buona
Peryton|2|M|Strappa i cuori, attacco in picchiata
Piercer|1/2|M|Si lascia cadere dal soffitto
Pixie|1/4|F|Invisibile, polvere magica, molti incantesimi innati
Purple Worm|15|M|Scava, inghiotte, pungiglione velenoso
Quaggoth|2|U|Selvaggi del Sottosuolo, servitori dei drow
Rakshasa|13|I|Immune agli incantesimi fino al 6° livello; vulnerabile alle armi magiche perforanti benedette
Remorhaz|11|M|Calore del corpo, inghiotte, vive nei ghiacci
Young Remorhaz|5|M|Calore del corpo, vive nei ghiacci
Revenant|5|N|Torna per vendicarsi di un nemico preciso, rinasce
Roc|11|M|Uccello gigantesco, afferra e porta via
Roper|5|M|Sembra una stalagmite, tentacoli che indeboliscono
Rust Monster|1/2|M|Antenne che arrugginiscono il metallo, mangia il ferro
Sahuagin|1/2|U|Diavoli del mare: vantaggio contro chi è ferito
Sahuagin Priestess|2|U|Sacerdotessa sahuagin, vantaggio contro chi è ferito
Sahuagin Baron|5|U|Capo sahuagin, vantaggio contro chi è ferito
Salamander|5|E|Calore del corpo, servitore degli efreeti
Fire Snake|1|E|Calore del corpo, servitore degli efreeti
Satyr|1/2|F|Musica magica, festaioli
Scarecrow|1|K|Sguardo terrificante
Shadow|1/2|N|Toglie Forza; chi muore così diventa un'ombra
Shambling Mound|5|P|Il fulmine lo cura; avvolge e soffoca
Shield Guardian|7|K|Protegge chi porta l'amuleto, assorbe danni
Minotaur Skeleton|2|N|Vulnerabile ai danni contundenti
Warhorse Skeleton|1/2|N|Vulnerabile ai danni contundenti
Red Slaad|5|A|Caos del Limbo, impianta uova nei corpi
Blue Slaad|7|A|Caos del Limbo, trasmette la malattia del caos
Green Slaad|8|A|Caos del Limbo, cambia forma
Gray Slaad|9|A|Caos del Limbo, incantesimi
Death Slaad|10|A|Caos del Limbo, incantesimi
Specter|1|N|Prosciuga la vita, incorporeo
Poltergeist|1/2|N|Incorporeo e invisibile, scaglia gli oggetti
Gynosphinx|11|M|Leggendaria, guardiana di enigmi
Androsphinx|17|M|Leggendaria, guardiana di enigmi, ruggito
Sprite|1/4|F|Legge l'allineamento nel cuore, frecce che addormentano
Stirge|1/8|B|Si attacca e succhia il sangue
Succubus/Incubus|4|I|Bacio che prosciuga, entra nei sogni, ammalia
Tarrasque|30|M|Leggendaria: il carapace riflette gli incantesimi a linea e a raggio, inghiotte, immunità vaste
Thri-kreen|1|U|Uomini-mantide, mimetismo, salto
Treant|9|P|Anima gli alberi, lancia massi, vulnerabile al fuoco
Troglodyte|1/4|U|Fetore che avvelena
Umber Hulk|5|M|Sguardo che confonde, scava nella roccia
Unicorn|5|C|Leggendario: cura, si teletrasporta, corno
Vampire|13|N|Leggendario: ammalia, si rigenera, diventa pipistrello o nebbia. Teme sole, acqua corrente, paletto nel cuore, inviti
Vampire Spawn|5|N|Si rigenera, teme sole e acqua corrente
Water Weird|3|E|Custode di fontane, annega la vittima
Will-o'-Wisp|2|N|Invisibile a scelta, consuma la vita dei morenti
Wraith|5|N|Incorporeo, prosciuga la vita, crea spettri
Xorn|5|E|Attraversa la pietra, mangia metalli preziosi
Yeti|3|M|Sguardo gelido che paralizza
Abominable Yeti|9|M|Sguardo gelido che paralizza, soffio di freddo
Yuan-ti Pureblood|1|U|Uomini serpente dei culti, veleno e incantesimi
Yuan-ti Malison|3|M|Uomini serpente dei culti, veleno e incantesimi
Yuan-ti Abomination|7|M|Uomini serpente dei culti, veleno e incantesimi
Mezzoloth|5|I|Mercenario yugoloth, si teletrasporta
Nycaloth|9|I|Mercenario yugoloth, si teletrasporta
Arcanaloth|12|I|Mercenario yugoloth incantatore, si teletrasporta
Ultroloth|13|I|Capo yugoloth, ipnotizza, si teletrasporta
Ogre Zombie|2|N|Resiste a 0 PF con un TS su Cos, salvo danni radiosi o critici
Beholder Zombie|5|N|Resiste a 0 PF con un TS su Cos, raggi oculari
Draft Horse|1/4|B|Traino di carri
Riding Horse|1/4|B|Cavalcatura da viaggio
Warhorse|1/2|B|Cavallo addestrato alla battaglia, carica
Mastiff|1/8|B|Cane da guardia
Mule|1/8|B|Bestia da soma
Camel|1/8|B|Cavalcatura del deserto
Black Bear|1/2|B|Predatore delle foreste
Brown Bear|1|B|Predatore delle foreste
Lion|1|B|Tattica di branco, balzo
Tiger|1|B|Balzo, agguato
Polar Bear|2|B|Predatore dei ghiacci
Elephant|4|B|Carica che travolge
Mammoth|6|B|Carica che travolge
Giant Ape|7|B|Lancia massi
Killer Whale|3|B|Predatore marino
Giant Eagle|1|B|Cavalcatura volante intelligente
Giant Scorpion|3|B|Chele e pungiglione velenoso
Giant Crocodile|5|B|Morso che afferra, coda
Giant Shark|5|B|Frenesia di sangue
Cat|0|B|Famiglio
Owl|0|B|Famiglio, vola senza farsi notare
Rat|0|B|Famiglio
Raven|0|B|Famiglio, imita le voci
Bat|0|B|Famiglio, ecolocalizzazione
Frog|0|B|Famiglio
Hawk|0|B|Famiglio, vista acuta
Swarm of Bats|1/4|B|Sciame: occupa lo spazio dei nemici
Swarm of Rats|1/4|B|Sciame: occupa lo spazio dei nemici
Swarm of Insects|1/2|B|Sciame: occupa lo spazio dei nemici
Swarm of Poisonous Snakes|2|B|Sciame velenoso
Swarm of Quippers|1|B|Sciame di pesci carnivori
Awakened Shrub|0|P|Arbusto risvegliato dalla magia
Awakened Tree|2|P|Albero risvegliato dalla magia
Blink Dog|1/4|F|Si teletrasporta a brevi salti
Death Dog|1|M|Cane a due teste, morso che ammala
Worg|1/2|M|Lupo malvagio, cavalcatura dei goblin
Winter Wolf|3|M|Soffio di freddo, tattica di branco
Commoner|0|U|Popolano
Tribal Warrior|1/8|U|Guerriero di tribù, tattica di branco
Acolyte|1/4|U|Accolito di un tempio, piccoli incantesimi
Noble|1/8|U|Aristocratico, para i colpi
Scout|1/2|U|Esploratore con arco
Spy|1|U|Attacco furtivo, abilità sociali
Priest|2|U|Sacerdote, incantesimi divini
Berserker|2|U|Combattente furioso
Cult Fanatic|2|U|Capo di culto, incantesimi
Druid|2|U|Incantatore della natura
Knight|3|U|Cavaliere, guida e ispira gli alleati
Gladiator|5|U|Combattente da arena, para i colpi
Assassin|8|U|Assassinio a sorpresa, veleno
Archmage|12|U|Incantatore di 18° livello, resiste alla magia
"""

COLORS = [  # name, Italian, breath type, shape, CRs wyrmling / young / adult / ancient
    ("nero", "Acido", "linea", [2, 7, 14, 21]), ("blu", "Fulmine", "linea", [3, 9, 16, 23]),
    ("verde", "Veleno", "cono", [2, 8, 15, 22]), ("rosso", "Fuoco", "cono", [4, 10, 17, 24]),
    ("bianco", "Freddo", "cono", [2, 6, 13, 20]), ("d'ottone", "Fuoco", "linea", [1, 6, 13, 20]),
    ("di bronzo", "Fulmine", "linea", [2, 8, 15, 22]), ("di rame", "Acido", "linea", [1, 7, 14, 21]),
    ("d'oro", "Fuoco", "cono", [3, 10, 17, 24]), ("d'argento", "Freddo", "cono", [2, 9, 16, 23]),
]
METAL = {"d'ottone": "o soffio che addormenta", "di bronzo": "o soffio che respinge", "di rame": "o soffio che rallenta",
         "d'oro": "o soffio che indebolisce", "d'argento": "o soffio che paralizza"}
TYPE_WORD = {"Acido": "acido", "Fulmine": "fulmine", "Veleno": "veleno", "Fuoco": "fuoco", "Freddo": "freddo"}
# monsters already in the app (2024 SRD values) are not repeated
SKIP = {"Goblin", "Goblin Boss", "Bugbear", "Gnoll", "Hobgoblin", "Kobold", "Skeleton", "Zombie", "Wolf", "Dire Wolf",
        "Giant Spider", "Ogre", "Orc", "Ghoul", "Mimic", "Gelatinous Cube", "Wight", "Owlbear", "Troll", "Veteran",
        "Mage", "Bandit", "Bandit Captain", "Cultist", "Guard", "Thug", "Giant Rat"}
WORDS = {2: "Due", 3: "Tre", 4: "Quattro"}


def prof(cr):
    return 2 if cr < 5 else min(9, 2 + int((cr - 1) // 4))


def stats(cr):
    """Estimated AC, HP, initiative, attack bonus, attacks per round, damage of one attack, save DC."""
    c = float(cr)
    ac = 12 if c < 1 else min(22, 13 + int(c // 3))
    hp = {0: 4, 0.125: 9, 0.25: 13, 0.5: 22}.get(c) or round(c * 16 + 14)
    ini = 1 if c < 1 else min(6, 1 + int(c // 4))
    bonus = (2 if c == 0 else 4) if c < 1 else prof(c) + 3
    dpr = {0: 2, 0.125: 4, 0.25: 5, 0.5: 7}.get(c) or 6 * c + 3
    times = 1 if c < 3 else 2 if c < 11 else 3 if c < 20 else 4
    per = dpr / times
    mod = min(10, 1 if c < 1 else 2 + int(c // 4))
    die = 6 if c < 1 else 8 if c < 10 else 10
    n = max(1, round((per - mod) / ((die + 1) / 2)))
    if c == 0:
        dmg = "1d4"
    else:
        dmg = "%dd%d+%d" % (n, die, mod)
    dc = 8 + prof(c) + min(8, 3 + int(c // 4))
    return ac, hp, ini, bonus, times, dmg, dc


ATTACK = {"Bestia": "morso", "Drago": "artigli", "Umanoide": "arma", "Gigante": "colpo", "Non morto": "colpo",
          "Costrutto": "colpo", "Melma": "pseudopodo", "Vegetale": "colpo"}
END = "Monster Manual 2014: CA, PF e attacchi stimati dal GS, verifica sul manuale"


def entry(name, cr, typ, note, extra=""):
    ac, hp, ini, bonus, times, dmg, dc = stats(cr)
    word = ATTACK.get(typ, "colpo")
    atk = ("%s attacchi: %s +%d, %s" % (WORDS[times], word, bonus, dmg)) if times > 1 else "%s +%d, %s" % (word.capitalize(), bonus, dmg)
    parts = [atk]
    if extra:
        parts.append(extra % {"dc": dc})
    if note:
        parts.append(note)
    parts.append(END)
    return [name, typ, ac, hp, ini, cr_text(cr), ". ".join(parts)]


def cr_text(cr):
    f = Fraction(cr).limit_denominator(8)
    return str(f.numerator) if f.denominator == 1 else "%d/%d" % (f.numerator, f.denominator)


out = []
for ln in ROWS.strip().splitlines():
    name, cr, t, note = ln.split("|")
    if name in SKIP:
        continue
    out.append(entry(name, Fraction(cr), T[t], note))
defs = {}
for col, dtype, shape, crs in COLORS:
    for age, cr in zip(["Cucciolo di drago %s", "Giovane drago %s", "Drago %s adulto", "Drago %s antico"], crs):
        name = age % col
        if name in ("Cucciolo di drago rosso", "Giovane drago rosso"):
            continue
        dice = round(cr * 1.1) + 3
        breath = "Soffio di %s (ricarica 5-6): %s, %dd%s %s, TS %s CD %%(dc)d" % (
            dtype.lower() if dtype != "Veleno" else "veleno", shape, dice, "6" if dtype in ("Fuoco", "Fulmine", "Acido", "Veleno") else "8",
            TYPE_WORD[dtype], "Cos" if dtype in ("Veleno", "Freddo") else "Des")
        note = ("Drago metallico, %s" % METAL[col]) if col in METAL else "Drago cromatico"
        if age.startswith("Drago"):
            note += ", leggendario con tana"
        out.append(entry(name, cr, "Drago", note, breath))
        defs[name] = {"immune": dtype}

out.sort(key=lambda e: (float(Fraction(e[5])), e[0]))


def gd(v):
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return str(v)


lines = ["class_name MonsterManual", "## Creatures of the Monster Manual (2014) for personal use: names, type,",
         "## challenge rating and a short play note come from the summaries of the",
         "## dnd5e-monster-manual skill; AC, HP, initiative, attacks and breath",
         "## weapons are estimated from the CR with a fixed formula, not taken from",
         "## the book. Generated file: edit the generator, not this list.",
         "## Same shape as Rules.MONSTERS: [name, type, AC, HP, init mod, CR, notes].", "",
         "const LIST: Array = ["]
for e in out:
    lines.append("\t[" + ", ".join(gd(x) for x in e) + "],")
lines += ["]", "", "## Dragon immunities by name.", "const DEFENSES := {"]
for k, v in defs.items():
    lines.append("\t%s: {\"immune\": %s}," % (gd(k), gd(v["immune"])))
lines += ["}", ""]
open(__import__("os").path.join(__import__("os").path.dirname(__file__), "..", "scripts", "monster_manual.gd"), "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print(len(out), "creatures,", len(defs), "dragons")
