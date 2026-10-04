# CraftersAddressBook

CraftersAddressBook es un addon para World of Warcraft 3.3.5 que guarda, a nivel de cuenta, contactos que comparten links de profesion por chat.

## Uso

1. Cuando otro personaje comparta un link de profesion, hace click en el link.
2. El addon pregunta si queres agregar ese personaje y esa profesion a la agenda.
3. Mostra la agenda con `/cab`.
4. Usa `Refrescar estados` o `/cab refresh` para consultar manualmente si los contactos estan online.

El addon no refresca estados automaticamente. Solo consulta online/offline cuando usas el boton o el comando.
El boton del minimapa muestra la agenda con click izquierdo, refresca estados con click derecho y se puede arrastrar para moverlo.

## Funciones

- Guarda contactos account-wide con `SavedVariables`.
- Captura links de profesion `trade:` desde chat.
- Permite abrir de nuevo el link guardado desde la ventana del addon.
- Abrir un link desde la lista no dispara el popup de refresco.
- Si el link ya existe, ofrece actualizar el cache local de recetas.
- Permite borrar una profesion con `[x]` y confirmacion.
- Permite borrar un contacto completo con la `[x]` junto al nombre.
- Muestra online/offline con indicador verde/rojo.
- Incluye boton de minimapa movible y configurable.
- Incluye placeholder en `Interface > AddOns > CraftersAddressBook` para configuraciones futuras.
- Incluye version de addon y version de esquema de datos.

## Comandos

- `/cab`: muestra la lista.
- `/cab show`, `/cab list`, `/cab lista`: muestra la lista.
- `/cab close`: cierra la ventana.
- `/cab toggle`: abre o cierra la ventana.
- `/cab refresh`: refresca estados online/offline manualmente.
- `/cab options`: abre el panel de opciones placeholder.
- `/cab debug`: muestra estado interno de la ventana para diagnostico.
- `/cab minimap`: muestra u oculta el boton del minimapa.
- `/cab minimap show`: muestra el boton del minimapa.
- `/cab minimap hide`: oculta el boton del minimapa.
- `/cab version`: muestra version del addon y del esquema de datos.
- `/cab help`: muestra ayuda corta.

## Datos guardados

La base se guarda en:

```lua
CraftersAddressBookDB
```

Estructura principal:

```lua
CraftersAddressBookDB = {
  schemaVersion = 1,
  addonVersion = "0.1.8",
  contacts = {
    ["nombre"] = {
      name = "Nombre",
      online = false,
      professions = {
        ["alquimia"] = {
          professionName = "Alquimia",
          link = "|cffffd000|Htrade:...|h[Alquimia]|h|r",
          rawLink = "trade:...",
          recipes = {},
          recipeCount = 0,
        },
      },
    },
  },
}
```

## Versionado

El proyecto usa SemVer.

- Version actual: `0.1.8`.
- La version visible para WoW vive en `CraftersAddressBook.toc`.
- La version de datos vive en `DB_SCHEMA_VERSION` dentro de `Core.lua`.
- Los cambios se documentan en `CHANGELOG.md`.
- Para subir una version, usar:

```bash
sh scripts/bump-version.sh 0.2.0
```

## Compatibilidad

Disenado para clientes 3.3.5 / Interface `30300`.

No requiere Ace ni otras librerias externas.
