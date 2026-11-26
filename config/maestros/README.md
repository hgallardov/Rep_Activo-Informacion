# Maestros iniciales (semilla)

Archivos CSV separados por `;`, en UTF-8, que carga `scripts/04-Import-MasterData.ps1`.

| Archivo | Lista | Observaciones |
|---|---|---|
| `entidades.csv` | Entidades | Completar el RUT de cada entidad. `AMBAS` es el valor para activos compartidos (RN-13). |
| `gerencias.csv` | Gerencias | **Ejemplo ilustrativo**: reemplazar por el organigrama vigente de ambas entidades. `Entidad` = Title de la entidad. Las gerencias corporativas se registran con entidad *Ambas* y `RN_EsCorporativa = true`. |
| `procesos.csv` | Procesos | Crear desde el mapa de procesos / BIA (columna `Gerencia` = Title de la gerencia). |
| `cargos.csv` | Cargos | Lo entrega la Gerencia de Personas: `Title;Gerencia;Entidad;TitularUPN;SubroganteUPN;RN_PuedeSerDueno;Jefatura`. |
| `terceros.csv` | Terceros | Desde el registro de proveedores y el registro NCG 573. |

El código de gerencia (`RN_Codigo`, 2 a 6 letras/dígitos) forma parte del ID del activo y **no debe cambiarse** una vez creados activos (RN-01).
