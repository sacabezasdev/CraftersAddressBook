# Changelog

Todas las versiones siguen SemVer.

## 0.1.8 - 2026-09-29

- Abrir un link desde el listado ya no ofrece refrescar el registro.
- Reemplazado el indicador de estado por un punto coloreado compatible con clientes 3.3.5.

## 0.1.7 - 2026-09-29

- Agregado boton `[x]` junto al nombre para borrar un contacto completo.
- Agregada confirmacion separada para borrar contacto y todas sus profesiones.

## 0.1.6 - 2026-09-29

- Los contactos sin profesiones guardadas se limpian al cargar para quitar filas fantasma creadas por versiones anteriores.

## 0.1.5 - 2026-09-29

- Corregido guardado de profesiones dentro de cada contacto.
- Agregado mensaje de confirmacion cuando una profesion queda guardada.

## 0.1.4 - 2026-09-29

- Corregido uso de `math.mod`, no disponible en algunos clientes 3.3.5.

## 0.1.3 - 2026-09-29

- La ventana de la agenda ahora se muestra en strata alto y top-level para no quedar detras de otras ventanas.
- El boton `Abrir agenda` del panel de opciones cierra `InterfaceOptionsFrame` antes de abrir la lista.
- Agregado `/cab debug` para diagnosticar si la ventana se crea y queda visible.

## 0.1.2 - 2026-09-29

- `/cab` ahora muestra explicitamente la lista en vez de alternar la ventana.
- Click izquierdo en el boton del minimapa ahora muestra la lista.
- Agregados alias `/cab show`, `/cab list`, `/cab lista`, `/cab close`, `/cab toggle` y `/cab options`.
- Agregado panel placeholder en `Interface > AddOns > CraftersAddressBook`.

## 0.1.1 - 2026-09-29

- Agregado boton de minimapa movible.
- Agregados comandos `/cab minimap`, `/cab minimap show` y `/cab minimap hide`.
- Click izquierdo en el boton abre/cierra la agenda; click derecho refresca estados.

## 0.1.0 - 2026-09-29

- Implementacion inicial del addon.
- Captura de links de profesion desde chat.
- Confirmacion para agregar, refrescar cache y borrar profesiones.
- Ventana `/cab` con contactos, links guardados y estado online/offline.
- Refresco manual de estados mediante consultas `/who`.
- SavedVariables account-wide.
- Version de addon y esquema de datos.
