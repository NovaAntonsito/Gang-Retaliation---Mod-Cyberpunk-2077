# Changelog - Gang Retaliation

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
