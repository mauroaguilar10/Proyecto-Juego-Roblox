# ARCHITECTURE

Juego de **Duelos 1v1** + **farmeo en Mazmorras** + **Tienda de armas**.
Stack: Luau `--!strict`, Rojo 7.3+ (archivos `.luau`).

## 1. Mapeo Rojo

| Carpeta         | Instancia en Roblox                              | Tipo        |
| --------------- | ------------------------------------------------ | ----------- |
| `src/Shared`    | `ReplicatedStorage.Shared`                       | Folder      |
| `src/Server`    | `ServerScriptService.Server`                     | Script      |
| `src/Client`    | `StarterPlayer.StarterPlayerScripts.Client`      | LocalScript |

`ReplicatedStorage.Remotes` **no** está en el repo: lo crea `Shared/Remotes` en runtime.

## 2. Propiedad de carpetas

| Ruta                     | Dev A (Combate/Duelos) | Dev B (Economía/Mazmorra/UI) |
| ------------------------ | :--------------------: | :--------------------------: |
| `src/Server/Combat/**`   | ✅ escribe              | ❌                            |
| `src/Client/Combat/**`   | ✅ escribe              | ❌                            |
| `src/Server/Economy/**`  | ❌                      | ✅ escribe                    |
| `src/Client/Economy/**`  | ❌                      | ✅ escribe                    |
| `src/Shared/**`          | 🔒 PR + review del otro | 🔒 PR + review del otro       |
| `init.*.luau`, `default.project.json`, `ARCHITECTURE.md` | 🔒 PR + review del otro | 🔒 PR + review del otro |

**Reglas**

- Prohibido hacer `require` de un módulo de la vertical ajena. La comunicación entre
  verticales es **solo** vía Attributes (sección 3) y módulos de `src/Shared`.
- Cada dev trabaja en ramas `feat/combat-*` o `feat/economy-*`; `main` solo recibe PRs.
- Agregar un remote = editar `Shared/Remotes.luau` (lista **y** tipo) en un PR propio.

## 3. Contrato de Attributes

El **escritor** es el único que puede hacer `SetAttribute`. Los demás solo leen
(`GetAttribute` / `GetAttributeChangedSignal`). Todos los escritores son **servidor**.

| Attribute        | Instancia                               | Tipo      | Valores                                          | Escritor (servidor)          | Lectores                         |
| ---------------- | --------------------------------------- | --------- | ------------------------------------------------ | ---------------------------- | -------------------------------- |
| `Gold`           | `Player`                                | `number`  | entero ≥ 0                                       | `DataService` (B)            | `UIController`, `ShopService`    |
| `EquippedWeapon` | `Player`                                | `string`  | clave válida de `WeaponData.Weapons`             | `ShopService` / `DataService` (B) | `CombatService`, `CombatController`, `UIController` |
| `InDuel`         | `Player`                                | `boolean` | `true` durante un duelo (incluye cuenta regresiva) | `ArenaService` (A)           | `ShopService`, `DungeonService`, `UIController` |
| `CombatState`    | `Humanoid` (jugadores y enemigos)       | `string`  | `"Idle"` \| `"Attacking"` \| `"Stunned"` \| `"Dead"` | `CombatService` (A)          | `CombatController`, `UIController`, `DungeonService` |
| `LastAttacker`   | `Humanoid` de enemigos de mazmorra      | `number`  | `UserId` del último jugador que golpeó (0 = nadie) | `CombatService` (A)          | `DungeonService` (recompensa en oro) |
| `Stamina`        | `Humanoid` de jugadores                 | `number`  | `0..100` (aguante para bloquear y esquivar)       | `CombatService` (A)          | `CombatController`, `HealthBarController` |
| `Blocking`       | `Humanoid` de jugadores                 | `boolean` | `true` mientras bloquea                           | `CombatService` (A)          | `CombatController` |
| `ComboStep`      | `Humanoid` de jugadores                 | `number`  | `1..3`, golpe del combo en curso (0 = ninguno)    | `CombatService` (A)          | `CombatController` |
| `Wave`           | `workspace.Mazmorra`                    | `number`  | oleada actual (0 = todavía ninguna)               | `DungeonService` (B)         | `UIController` |
| `EnemiesLeft`    | `workspace.Mazmorra`                    | `number`  | guardianes vivos de la oleada                     | `DungeonService` (B)         | `UIController` |
| `NextWaveAt`     | `workspace.Mazmorra`                    | `number`  | `workspace:GetServerTimeNow()` de la próxima oleada (0 = ninguna pendiente) | `DungeonService` (B) | `UIController` |
| `Center` / `Size`| `workspace.Mazmorra`                    | `Vector3` / `number` | centro y lado de la sala (para saber si el jugador está adentro) | `DungeonService` (B) | `UIController` |

**Progreso guardado (DataService, B):** `bestWave` (mejor oleada alcanzada) y `kills` (guardianes
derrotados) se guardan en el perfil y se muestran en `Player.leaderstats` ("Mejor oleada", "Guardianes").
`RecordsService` publica la mejor oleada en el OrderedDataStore `BestWave_v1` y la muestra en el
cartel de récords del lobby. Las armas de GamePass se vuelven a verificar cada vez que el jugador entra.

**Avisos de Economía (`Notify`, S→C):** además de texto, `DungeonService` manda
`{ Kind = "Gold", Amount: number, Position: Vector3 }` al jugador que mató a un guardián;
`UIController` muestra el «+N» en el mundo y las monedas volando al contador.

**Lobby (B):** `LobbyService` arma el puesto de la tienda; su `ProximityPrompt` tiene el Attribute
`OpenShop = true` y `UIController` abre la tienda al activarlo (sin pasar por el servidor).
`DungeonService` arma el arco de entrada a la mazmorra y `RecordsService` el cartel de récords.

**Garantías**

- `EquippedWeapon` siempre existe desde que el jugador entra (por defecto `WeaponData.DEFAULT_WEAPON`).
  Combat debe usar `WeaponData.GetOrDefault()` por si llega un valor inválido.
- `Gold` solo cambia en el servidor; Combat **nunca** lo modifica. Si en el futuro los duelos
  dan oro, se amplía este contrato (p. ej. un BindableEvent en `Shared`) vía PR.
- `LastAttacker` se escribe **antes** de aplicar el daño letal, así `DungeonService`
  puede leerlo al escuchar `Humanoid.Died`.
- Mientras `InDuel == true`, Economy debe bloquear compra/equipamiento y entrada a mazmorra.

**Reglas de daño (CombatService)**

- **Enemigo** = cualquier `Model` con `Humanoid` (y `Humanoid.RootPart`) que no sea el personaje
  de un jugador. `DungeonService` solo necesita spawnear Models así; no hace falta tag.
- **PvP** solo entre oponentes del mismo duelo (`ArenaService.AreOpponents`). Fuera de duelo
  los jugadores no se dañan entre sí; en duelo no se puede dañar a enemigos.
- **Arma = Tool de inventario.** `WeaponVisualService` da a cada personaje una única Tool
  (Attribute `WeaponId`) del arma de `EquippedWeapon`; se saca/guarda desde la barra de Roblox.
  Solo se ataca con ella en la mano (`WeaponVisualService.IsWeaponHeld`). No crear otras Tools de arma.

- **Bloqueo / esquive / combo.** Bloquear (solo golpes de frente) reduce el daño y gasta
  `Stamina`; en los primeros 0,2 s es un *parry* (0 daño, atacante aturdido). Sin aguante → guardia rota.
  Esquivar da invulnerabilidad breve. El 3.er golpe del combo hace ×1,5 de daño y empuja más.
  Mientras bloquea, `CombatService` baja temporalmente `Humanoid.WalkSpeed` y lo restaura al soltar.

**Remotes de combate**

- `CombatAttack` (C→S): primer argumento = acción. `()` o `("Attack")` atacar,
  `("Block", boolean)` empezar/soltar bloqueo, `("Dash")` esquivar.
- `CombatFeedback` (S→C, al atacante y a la víctima): `{ Kind: "Hit" | "Blocked" | "Parry" | "GuardBreak",
  Attacker: Player, Target: Model, Damage: number, Killed: boolean, WeaponId: string, Combo: number,
  Knockback: Vector3? }` (`Knockback` solo en el payload que recibe la víctima).

**Remotes de duelo (para la UI de Economy)**

`DuelController` (Combat) muestra notificaciones nativas mínimas. La UI definitiva puede
escuchar los mismos eventos sin tocar Combat:

- `DuelInvite` (S→C): `(challenger: Player)`. Responder con
  `DuelResponse:FireServer(challenger, accepted: boolean)`.
- `DuelStateChanged` (S→C): `payload` con
  `State: "InviteSent" | "Declined" | "Unavailable" | "Countdown" | "Fight" | "End"`, `Opponent: Player?`,
  `Seconds: number?` (Countdown), `EndsAt: number?` (Fight; `workspace:GetServerTimeNow()` del fin por tiempo),
  `Winner: Player?` (End; `nil` = empate) y
  `Reason: "Defeat" | "Forfeit" | "Timeout"?` (End).

## 4. Contrato de módulos

Todo `ModuleScript` dentro de `Combat/` o `Economy/` (servidor y cliente) **debe**
devolver una tabla con un método `:Init()`:

```lua
--!strict
local MyService = {}

function MyService:Init() end

return MyService
```

- Los cargadores `init.server.luau` / `init.client.luau` llaman a `:Init()` de cada
  módulo dentro de `pcall` + `task.spawn`. Un módulo que falla **no** afecta a los demás.
- `:Init()` puede ceder (yield) sin bloquear a otros módulos.
- No hay orden garantizado entre módulos: nunca asumas que otro servicio ya inicializó.
  Usa `GetAttributeChangedSignal` / `WaitForChild` en lugar de dependencias directas.
- Módulos auxiliares que **no** son servicios deben ir en una subcarpeta
  (p. ej. `Combat/Util/`), ya que el cargador solo recorre hijos directos.
- Servidor autoritativo: el cliente solo **solicita** (RemoteEvent/Function); el servidor
  valida todo (cooldown, rango, oro, propiedad del arma).
