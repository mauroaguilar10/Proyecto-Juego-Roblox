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
| `CombatState`    | `Humanoid` (jugadores y enemigos)       | `string`  | Jugadores: `"Idle"` \| `"Windup"` \| `"Charging"` \| `"Attacking"` \| `"Recovery"` \| `"Parrying"` \| `"Blocking"` \| `"PostureBroken"` \| `"Stunned"` \| `"Dashing"` \| `"Dead"`. Enemigos: solo `"Idle"` \| `"Stunned"` \| `"Dead"` | `CombatService` (A)          | `CombatController`, `UIController`, `DungeonService` |
| `LastAttacker`   | `Humanoid` de enemigos de mazmorra      | `number`  | `UserId` del último jugador que golpeó (0 = nadie) | `CombatService` (A)          | `DungeonService` (recompensa en oro) |
| `Posture`        | `Humanoid` de jugadores                 | `number`  | `0..100`; sube al bloquear/ser desviado, 100 = guardia rota | `CombatService` (A)          | `CombatController`, `HealthBarController` |
| `ComboStep`      | `Humanoid` de jugadores                 | `number`  | `1..3`, golpe del combo en curso (0 = ninguno)    | `CombatService` (A)          | `CombatController` |
| `Wave`           | `workspace.Mazmorra.Sala_<UserId>`      | `number`  | oleada actual (0 = todavía ninguna)               | `DungeonService` (B)         | `UIController` |
| `EnemiesLeft`    | `workspace.Mazmorra.Sala_<UserId>`      | `number`  | guardianes vivos de la oleada                     | `DungeonService` (B)         | `UIController` |
| `NextWaveAt`     | `workspace.Mazmorra.Sala_<UserId>`      | `number`  | `workspace:GetServerTimeNow()` de la próxima oleada (0 = ninguna pendiente) | `DungeonService` (B) | `UIController` |
| `Center` / `Size`| `workspace.Mazmorra.Sala_<UserId>`      | `Vector3` / `number` | centro y lado de la sala (para saber si el jugador está adentro) | `DungeonService` (B) | `UIController` |

**Mazmorras individuales (DungeonService, B):** cada jugador que cruza el arco recibe su propia sala
(`workspace.Mazmorra.Sala_<UserId>`, a 160 studs de altura y separadas 160 en X) y empieza en la oleada 1.
No hay portal de salida: el botón rojo "Exit" del HUD (pide confirmación con "Sure?") manda el remote
`LeaveDungeon` (C→S) y el servidor te devuelve delante del arco. La sala se borra al tocar "Exit", al pasar 8 s fuera de ella (muerte, duelo) o al irse del juego.
Los guardianes solo atacan al dueño de la sala. El arco del lobby está en `workspace.Mazmorra.Entrada`.

**Progreso guardado (DataService, B):** `bestWave` (mejor oleada alcanzada) y `kills` (guardianes
derrotados) se guardan en el perfil y se muestran en `Player.leaderstats` ("Mejor oleada", "Guardianes").
`RecordsService` publica la mejor oleada en el OrderedDataStore `BestWave_v1` y la muestra en el
cartel de récords del lobby. Las armas de GamePass se vuelven a verificar cada vez que el jugador entra.

**Pase del Vacío (DataService / ShopService, B):** el pase cuyo ID es `WeaponData.Weapons.VoidScythe.GamePassId`
da la Guadaña del Vacío y **duplica el oro de la mazmorra** (`DataService.GoldMultiplier`). Se verifica al
entrar y se activa en el momento de la compra (`MarketplaceService.PromptGamePassPurchaseFinished` en el
servidor). `DataService` escribe `Player.VoidPass` (`boolean`) y `UIController` lo lee para el botón del HUD.

**Armería (ArmorService / ArmorController, B):** piezas en `Shared/ArmorData` (3 sets × Casco, Pechera,
Pantalón) y su aspecto en `Shared/ArmorArt`. Remote `ArmorShop` (C→S→C: `"Get" | "Buy" | "Equip" | "Unequip"`).
Lo comprado y lo puesto se guarda en el perfil (`armorOwned`, `armorEquipped`). En el personaje, cada pieza
es un Model `Armadura_<Slot>` soldado al cuerpo; los accesorios que chocarían se guardan aparte y vuelven
al quitarla. `ArmorService` escribe `Humanoid.MaxHealth` (100 + vida de las piezas) y el Attribute
**`Humanoid.Armor`** (`number`, 0..0.6): reducción del daño recibido, que aplican `DungeonService` (guardianes)
y `CombatService` (duelos) antes de `TakeDamage`.
**Barra de vida (HealthHUD, B):** reemplaza la de Roblox (`SetCoreGuiEnabled(Health, false)`): "vida/máx HP"
dentro de la barra y color según el %. La tienda de armas ya no tiene botón en el HUD: se abre desde su puesto.

**Tienda de Robux (MonetizationService / PremiumShopController, B):** catálogo en `Shared/StoreData`
(productos de desarrollador: set de la Tormenta, Hoja del Fénix, Martillo del Trueno, potenciadores
Oro x2 y Daño x2 de 10 min y paquetes de oro). `MonetizationService` es el **único** que define
`MarketplaceService.ProcessReceipt`: anota cada `PurchaseId` en el perfil (`receipts`, no se entrega dos
veces), guarda y recién ahí devuelve `PurchaseGranted`. Armas con `Acquisition = "Robux"` y sets con
`Acquisition = "Robux"` solo se entregan por ahí (ShopService/ArmorService no los venden por oro).
El set del Vacío (`Acquisition = "VoidPass"`) se tiene mientras se tenga el Void Pass (`DataService.OwnsArmor`).
Potenciadores: vencen en `os.time()` (perfil `boosts`) y se publican como `Player.GoldBoostUntil` /
`Player.DamageBoostUntil` (`number`, tiempo de `workspace:GetServerTimeNow()`, 0 = inactivo).
"Oro x2" se multiplica con el Void Pass en `DataService.GoldMultiplier`; "Daño x2" lo aplica `CombatService`
solo contra enemigos (no jugadores).

**Códigos (CodeService, B):** remote `RedeemCode` (C→S→C, devuelve `ok, mensaje`). Los códigos viven solo
en el servidor; cada uno se canjea una vez por jugador (`redeemed` en el perfil). Un código puede dar oro o
el Void Pass; un pase dado por código se guarda en `bonusPasses` del perfil y se reactiva en cada entrada
sin consultar a Roblox.

**Modelos de armas (`Shared/WeaponArt`):** las armas detalladas (Colmillo de Escarcha, Lanza del Alba,
Hacha del Coloso) se arman una sola vez y las usan `WeaponModels` (el arma en la mano, mismo contrato:
Model "Weapon" + Grip) y `WeaponPreview` (la ficha de la tienda).

**Avisos de Economía (`Notify`, S→C):** además de texto, `DungeonService` manda
`{ Kind = "Gold", Amount: number, Position: Vector3 }` al jugador que mató a un guardián;
`UIController` muestra el «+N» en el mundo y las monedas volando al contador.

**Lobby (B):** `LobbyService` arma la ciudadela alrededor del spawn (`workspace.Lobby`): plaza, muralla,
torres, estatua, herrería, campamento, arena de duelos decorativa y el puesto de la tienda; su
`ProximityPrompt` tiene el Attribute `OpenShop = true` y `UIController` abre la tienda al activarlo
(sin pasar por el servidor). `DungeonService` arma el arco de entrada a la mazmorra (este del spawn) y
`RecordsService` el cartel de récords (oeste). Las piezas reutilizables están en `Economy/Lobby/Kit`.
- **Muñecos de práctica** (campo de entrenamiento): Models con `Humanoid` y partes ancladas;
  `CombatService` los golpea como a cualquier enemigo fuera de duelo. Se curan solos y no dan oro.
- **Iluminación:** `LobbyService` configura `Lighting` al arrancar (atardecer, `Atmosphere`, bloom).
  `UIController` la oscurece solo en el cliente mientras el jugador está en su sala de la mazmorra.

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

- **Ataque con compromiso.** Cada golpe es `Windup` (`WeaponData.WindupTime`) → `Attacking` (0,1 s,
  paso hacia adelante) → `Recovery` (`RecoveryTime`; más corta si conecta). Golpear a alguien en
  `Windup` lo interrumpe, salvo arma `Heavy` en sus últimos 0,15 s (hyperarmor).
- **Parry y postura.** Mantener F: los primeros 0,22 s son `Parrying`, después `Blocking`.
  Parry de frente → 0 daño, el atacante suma 35 de `Posture` y queda `Stunned` 1,1 s. Bloquear de frente
  → 0 daño y el defensor suma `PostureDamage`; con `Posture` 100 → `PostureBroken` 2 s (recibe ×1,5).
  Tocar F sin desviar nada pone el parry en cooldown 1,2 s. La postura baja sola tras 3 s sin bloquear ni recibir golpes.
- **Dash** (Q): 0,25 s, i-frames los primeros 0,12 s, cooldown 2 s. El 3.er golpe del combo hace ×1,5.
- **Movilidad.** `CombatService` es dueño de `WalkSpeed`, `JumpPower`/`JumpHeight` y `AutoRotate` de los
  personajes de jugadores: los guarda al aparecer y los ajusta según `CombatState`. Otro sistema que
  necesite cambiarlos debe coordinarlo con Combat. Los empujes usan `CombatService.ApplyPhysicalImpulse`
  (`LinearVelocity` en el plano XZ; nunca BodyMovers deprecados).

**Remotes de combate**

- `CombatAttack` (C→S): primer argumento = acción. `()` o `("Attack", aim: Vector3?)` atacar,
  `("ChargeStart")` / `("ChargeRelease", aim: Vector3?)` mantener/soltar el ataque (cargado = Damage + 5),
  `("Block", boolean)` mantener/soltar F, `("Dash")` esquivar.
- `CombatFeedback` (S→C, a los jugadores a ≤150 studs): `{ Kind: "Hit" | "Blocked" | "Parry" | "GuardBreak" | "Dodge",
  Attacker: Player, Target: Model, Damage: number, Killed: boolean, WeaponId: string, Combo: number,
  Interrupted: boolean, Hyperarmor: boolean, Intensity: number }` (`Intensity` 0..1 para hitstop/cámara).

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
