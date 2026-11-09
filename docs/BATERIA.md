# Batería

Planaby puede pasar horas abierta (el modo escritorio cargando, una sesión larga). La regla es
despertar solo para lo que se ve, y nada si no cambia. Las cuentas están en
`Shared/Engine/RefreshPolicy.swift`, con tests en `Tests/RefreshPolicyTests.swift`.

## Qué se ha cambiado

| Antes | Ahora |
|---|---|
| El temporizador se despertaba **cada segundo** siempre, aunque no hubiera sesión | Se despierta **justo cuando acaba la fase**. Sin sesión o en pausa, no se despierta |
| El halo de Enfoque se repintaba a 30 fps a pantalla completa siempre | Quieto, salvo en un **descanso en marcha** (como ya hacía el modo escritorio), y a 20 fps |
| Enfoque en pausa, el modo escritorio sin sesión y el reproductor sin música se repintaban cada segundo | **Cada minuto**, justo al cambiar de minuto (lo que se ve es la hora) |
| El modo escritorio leía la agenda y las comunicaciones del disco **cada segundo** | Al abrirlo, cuando llega algo nuevo y una vez por minuto |
| Spotify: la API web cada 3 s y un intento de reconexión cada 6 s, sin fin | Cada 4 s si suena, cada 15 s si no y cada 30 s con App Remote (que avisa él solo). Reconexión cada vez más espaciada: 6, 12, 24, 48 s y después cada minuto |
| El modo escritorio dejaba activada la lectura del estado de la batería al salir | Se desactiva al salir |

## Lo que ya estaba bien

- Los widgets se actualizan cada hora (agenda) o al acabar la fase (temporizador); iOS los
  limita además con su presupuesto.
- La pantalla solo se queda encendida en el modo escritorio **mientras carga**.
- No hay modos en segundo plano (ni ubicación ni audio): al salir, Planaby se duerme. Solo pide
  unos segundos extra al salir concentrándote, para el aviso de «Has salido de Planaby».
- El correo (IMAP) y los calendarios externos solo se miran al volver a la app y si ha pasado un
  rato.
- La IA local solo gasta mientras piensa; se carga al escribir y se suelta sola (ver
  [IA.md](IA.md)). La animación de carga va a 30 fps y solo mientras trabaja.

## Pruebas en el iPhone

1. Ajustes de iOS › Batería: tras un día normal, el porcentaje de Planaby con la pantalla
   encendida debe parecerse al tiempo que la has usado, y casi nada en segundo plano.
2. Modo escritorio cargando una noche, sin sesión: el reloj cambia justo al cambiar de minuto y el
   iPhone no se calienta.
3. Sesión de 25 minutos: la cuenta atrás va cada segundo y la fase cambia a su hora, con su aviso
   y la tarjeta «Has trabajado durante 25 minutos». En pausa, la cifra queda quieta.
4. Un descanso en marcha: el halo respira; en concentración y sin sesión, está quieto.
5. Spotify sonando en el modo escritorio: el cambio de canción se ve en unos segundos. Sin
   Spotify abierto, nada se queda intentando conectar sin parar (abre Spotify y vuelve: conecta).
