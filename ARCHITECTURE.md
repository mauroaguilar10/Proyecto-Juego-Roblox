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
| `LastAttacker`   | `Humanoid` de enemigos de mazmorra      | `number`  | `UserId` del último jugador que golpeó (0 = nadie) | `CombatService` (A)          | `DungeonService` (recompensas/drops) |

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
