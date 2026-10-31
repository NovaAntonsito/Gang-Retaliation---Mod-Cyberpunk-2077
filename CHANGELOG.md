# Changelog - Gang Retaliation

## [1.3.0] - 2026-10-31

### English

#### New
- **Bigger enemy health bar.** The bar over the enemy you look at can be scaled up (x1.5 by default,
  x1 to x2 in Mod Settings).
- **Flee line.** A yellow line on the enemy's health bar marks the health at which they'll run away
  if left last standing. It only shows when that ganger really can flee: not in scenes, vehicles or
  on bosses, so it never promises an escape that won't happen.
- **THREATS panel.** In combat, a box on the left lists the enemies targeting you. Each row shows
  the gang color, the name (the Nemesis name if it is one, otherwise the gang), the distance and a
  small health bar with its own flee line. Below the threshold, the bar turns amber.
  - The enemy you're looking at comes first, then Nemeses, then by distance. The rest show as
    "+N more".
  - It hides 3 s after combat and while the weapon wheel is open.
  - Same size at any resolution.
- **HUD options in Mod Settings** (new HUD category): enemy bar size, flee line on/off, threats
  panel on/off, panel X/Y position, size, background opacity and number of rows. Everything applies
  live, no restart needed.

#### Changed
- **Tracking a job no longer disables fleeing.** Before, with a main or side job tracked, nobody
  fled anywhere on the map, and almost everyone always tracks a job. Now fleeing is only blocked
  when V is within 150 m of that job's objective.
- **Gangers who flee and survive become Nemeses.** A ganger who fled and turned back to fight (so
  they don't leave the area) now becomes a Nemesis if still alive when combat ends, even with more
  health than the "wounded escape" threshold.
- **SMS-announced ambushes wait longer.** If they can't start (V in combat, indoors, in a vehicle),
  they retry for 30 minutes instead of 10 before being cancelled.

#### Fixed
- **Ambushes blocked by They Will Remember corpses.** The TWR squad check also counted dead members,
  which TWR doesn't remove while you're nearby. Now only living ones count.
- **Boss health bar stuck on screen.** When the Nemesis died, the ambush ended or you moved away
  (even by fast travel), the boss bar could stay at the top of the screen. It's now checked every
  second and removed if the Nemesis no longer exists, is dead or downed, or is more than 100 m away.
- **Nemeses spawning passive.** If the NPC wasn't ready when it spawned, it never entered combat
  and just stood there. Now, during the ambush, those still out of combat near V are provoked again
  every 3 s (up to 6 times).

### Español

#### Nuevo
- **Barra de vida del enemigo más grande.** La barra sobre el enemigo que mirás se puede agrandar
  (x1.5 por defecto, de x1 a x2 en Mod Settings).
- **Línea de huida.** Una línea amarilla en la barra del enemigo marca con cuánta vida va a huir si
  queda último en pie. Solo aparece cuando ese pandillero de verdad puede huir: no en escenas, en
  vehículos ni con jefes, así que nunca promete una huida que no va a pasar.
- **Panel AMENAZAS.** En combate, un recuadro a la izquierda lista a los enemigos que te tienen como
  objetivo. Cada fila lleva el color de la banda, el nombre (el del Némesis si lo es, si no el de la
  banda), la distancia y una barra de vida pequeña con su propia línea de huida. Por debajo del
  umbral, la barra se pone ámbar.
  - Primero el enemigo que mirás, después los Némesis y después por distancia. Los que no entran
    aparecen como "+N más".
  - Se oculta 3 s después del combate y mientras está abierta la rueda de armas.
  - Se ve del mismo tamaño en cualquier resolución.
- **Opciones de HUD en Mod Settings** (nueva categoría HUD): tamaño de la barra enemiga, línea de
  huida sí/no, panel de amenazas sí/no, posición X/Y del panel, tamaño, opacidad del fondo y
  cantidad de filas. Todo se aplica en vivo, sin reiniciar.

#### Cambiado
- **Seguir una misión ya no apaga las huidas.** Antes, con una misión principal o secundaria
  seguida, nadie huía en ningún lugar del mapa, y casi todos siguen siempre alguna misión. Ahora
  solo se bloquea la huida si V está a menos de 150 m del objetivo de esa misión.
- **Los que huyen y sobreviven se vuelven Némesis.** Un pandillero que huyó y vuelve a pelear para
  no salir de la zona ahora se convierte en Némesis si sigue vivo al terminar el combate, aunque
  tenga más vida que el umbral de "huida herida".
- **La emboscada anunciada por SMS espera más.** Si no puede salir (V en combate, bajo techo, en
  vehículo), reintenta durante 30 minutos en vez de 10 antes de cancelarse.

#### Arreglado
- **Emboscadas bloqueadas por cadáveres de They Will Remember.** El bloqueo por escuadrón de TWR
  contaba también a los miembros muertos, que TWR no borra mientras estés cerca. Ahora solo cuentan
  los vivos.
- **Barra de jefe trabada en pantalla.** Cuando el Némesis moría, la emboscada terminaba o te
  alejabas (incluso teletransportándote), la barra de jefe podía quedarse arriba de la pantalla.
  Ahora se revisa cada segundo y se quita si el Némesis ya no existe, está muerto o derribado, o
  quedó a más de 100 m.
- **Némesis que aparecían pasivos.** Si el NPC todavía no estaba listo cuando aparecía, no entraba
  en combate y se quedaba quieto. Ahora, mientras dura la emboscada, los que siguen fuera de combate
  cerca de V se vuelven a provocar cada 3 s (hasta 6 veces).

## [1.2.2] - 2026-10-29

### Arreglado
- **Crash al terminar un combate** (`GRDetection.OnPlayerCombatEnded`, reportado con They Will
  Remember, Dark Future y EDO). El texto de depuración se armaba siempre, aunque el log de
  depuración estuviera apagado, y la lista de candidatos se recorría mientras otro evento podía
  modificarla.
- **Némesis falsos con mods que borran NPCs.** Un pandillero que desaparece al acabar el combate
  (por ejemplo, un escuadrón de They Will Remember que el mod borra) ya no se asciende como
  "escapó herido".
- **"No se pudo escribir data/gang_retaliation.json".** Vortex no instalaba la carpeta `data`
  vacía y el mod no podía guardar a sus Némesis. Ahora viene con un archivo `.keep` adentro.

### Cambiado
- **Rendimiento.** La capa CET ya no consulta al juego en cada frame: todo va en un tick de 1 s.
  El menú NÉMESIS se reconstruye solo cuando cambian los datos, y no cada 2 s aunque esté
  cerrado. Medido con 44 Némesis: los picos bajan de 11 ms a 4 ms y casi no hay gasto en reposo.
- **Compatibilidad con They Will Remember.** Mientras haya un escuadrón de venganza de TWR en el
  mapa, no salen emboscadas, redadas de la NCPD ni escaramuzas de Gang Retaliation, para no
  sumar dos ataques a la vez. Sin TWR instalado no cambia nada.

## [1.2.1] - 2026-10-29

### Nuevo
- **Emboscadas en vehículo.** El Némesis y su escolta pueden llegar en coche, aparcar y bajarse.
  Si no hay sitio detrás de V, llegan a pie.
- **Casas de V.** Cerca de una casa de V no hay emboscadas (probabilidad 0 a menos de 60 m,
  normal a más de 300 m). El departamento H10 viene de fábrica; el resto se aprende al dormir
  2 noches en él.

### Arreglado
- **Emboscadas dentro del departamento o en pasillos.** Ahora solo aparecen a cielo abierto: si V
  está bajo techo, la emboscada anunciada espera a que salga. Tampoco salen en escenas donde V no
  puede sacar el arma.
- **Misiones que no se podían terminar porque el último enemigo huía.** No hay huidas en las
  misiones de historia que V tiene seguidas, y los NPCs del mundo ya no salen de la zona al huir.
- **Emboscadas atascadas.** Se cierran solas a los 40 s.
- Durante una emboscada, defenderse no cuenta como delito.

## [1.2] - 2026-10-28

### Nuevo
- **Redadas de la NCPD cerca de V.** Un Némesis de la zona y su escolta se enfrentan a una patrulla
  de 3 a 5 policías (más cuanto más alto el rango), a unos 30 m de V.
  - Probabilidad por minuto configurable en Mod Settings ("Redadas de la NCPD cerca de V", 10%),
    como mucho una cada 15 minutos.
  - V puede mirar, ayudar a la policía o ayudar a la banda. La banda nace hostil con V (así
    dispararle no es delito) y la policía, amistosa.
  - Durante la redada nadie huye: el Némesis pelea hasta el final.
  - Si el Némesis sobrevive, gana 2 de renombre y corre el rumor de que escapó.
- **Recompensa de la NCPD.** Si la banda cae entera con ayuda de V, la NCPD paga según el rango
  del Némesis: 1.000 / 2.500 / 5.000 eurodólares. Si V le pegó a algún policía, se descuenta la
  mitad "por gastos médicos de los agentes".
- **Contacto "NCPD" en el teléfono**, con su hilo "NCPD - Recompensas": 6 mensajes de pago
  normal y 3 de pago con descuento, en ES (con variantes para V mujer y V hombre) y EN.
- **Inmunidad ante la policía durante las redadas.** Desde que empieza hasta que termina y V
  enfunda el arma (como mucho 60 s después): nada de lo que haga V cuenta como delito, sin
  estrellas de búsqueda aunque una bala perdida le dé a un policía. Los policías de la redada se
  mantienen amistosos con V.
- **Tiroteos simulados con la NCPD** (fuera de cámara). Cada día, cada banda tiene una
  probabilidad (Mod Settings, "Tiroteos con la NCPD", 10%) de que la policía choque con uno de
  sus Némesis. Resultado: escapa (+2 renombre), muere (puede volver, como cualquier muerte
  normal) o lo arrestan 2-5 días. Mientras está arrestado no embosca ni sale en encargos. Todo
  llega como rumores.
- **Causa de muerte de cada Némesis.** Se registra quién le dio el último golpe: V (incluidos
  sus aliados, torretas y drones), la NCPD, otra banda u otra causa (caída, accidente). Se ve en
  el aviso y en el menú NÉMESIS (sección Caídos: "A manos de la NCPD", "A manos de Maelstrom"…).
- **Barra de vida de jefe** del juego para los Némesis vivos (no para su escolta), con su nombre
  completo. Se desactiva con el ajuste `bossBar`.

### Cambiado
- Solo las muertes a manos de V debilitan a la banda en la guerra de bandas. Un remate (disparo
  a la cabeza, explosión, desmembramiento) solo deja muerto para siempre al Némesis si lo dio V.
  Arreglo de compatibilidad con mods que añaden tiroteos entre bandas y policía (NCA).
- **Versión dev y versión release.** La carpeta de trabajo mantiene la ventana de CET
  "Gang Retaliation (dev)" con todos los botones de debug. El zip de `release.py` sale con una
  ventana mínima (campaña, Némesis vivos y muertos, día de juego).
- Nuevos botones de debug: "Debug: force NCPD clash" y "Debug: NCPD raid now".

### Corregido
- **Crash intermitente al huir el último en pie.** La huida se ejecutaba dentro del golpe de V o
  de la muerte de un compañero, a veces sobre un NPC que se estaba muriendo. Ahora se anota y se
  ejecuta en el siguiente tick, después de volver a comprobar que el NPC siga vivo. Además, si V
  y el NPC están pegados, la dirección de huida ya no sale inválida.
- La policía disparaba a V aunque la ayudara en una redada: la banda nacía neutral, así que
  atacarla contaba como delito.
- No se cobraba la recompensa si el Némesis huía a un sitio inalcanzable en mitad de la redada.
- Los mensajes de la policía hablan de "eurodólares" (oficial), no de "eddies" (jerga callejera).
- Se quitó el aviso en pantalla de la recompensa, que repetía lo que ya decía el SMS. Solo sale
  si el SMS no se puede mandar.

### Aviso
- La v1.0.0 publicada en Nexus incluía la ventana de debug completa de CET. Esta versión la
  quita del zip de release.
