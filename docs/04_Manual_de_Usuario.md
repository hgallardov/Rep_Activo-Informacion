# 04 · Manual de usuario – Inventario de Activos de Información

**Para:** Dueños de activos (gerentes y jefaturas), Delegados de registro, Custodios, CISO, DPO, Riesgos, CSI y Auditoría Interna de Renta Nacional Seguros Generales (RNSG) y Seguros de Vida (RNSV).
**Acceso:** pestaña *Inventario de Activos* en el canal SGSI de Microsoft Teams, o desde el navegador o la app Power Apps del móvil. Requiere MFA.

> El inventario es información **Reservada**. No registre datos de personas (RUT, nombres de clientes, etc.), contraseñas ni configuraciones: solo describa **qué tipo de información** existe y **dónde** está.

## 1. Conceptos clave
* **Dueño del activo:** el *cargo* (no la persona) que clasifica, autoriza accesos y acepta el riesgo residual. Si cambia la persona del cargo, los activos no cambian.
* **Delegado de registro:** persona designada por el Dueño para registrar; puede guardar borradores, pero **no declarar**.
* **Niveles** (de mayor a menor sensibilidad): **Confidencial · Reservado · Uso Interno · Pública**. Todo activo sin clasificar se trata como Confidencial.
* **Reglas automáticas** (no dependen del criterio de cada usuario):
  * Con datos personales → mínimo **Reservado**; con datos sensibles → mínimo **Confidencial**.
  * Información confiada por terceros → no menos que lo acordado con ellos.
  * Crítico = alguna dimensión C-I-D en *Alta*.
  * Confidencial y Reservado exigen la lista de **cargos autorizados**.
  * Revisión integral cada 12 meses (6 si es crítico o tiene datos personales); revisión de accesos cada 6 meses para Confidencial y Reservado.

## 2. Inicio – Mis pendientes
Muestra lo que requiere su acción: activos observados, revisiones por vencer, revisiones de accesos, excepciones por vencer y (para CISO/DPO) validaciones pendientes. Los avisos también llegan por Outlook y Teams a 30, 15 y 0 días del vencimiento.

## 3. Registrar un activo (asistente de 5 pasos, ~10 minutos)
1. **Identificación:** entidad (RNSG, RNSV o *Ambas* si sirve a las dos compañías; en ese caso indique la gerencia contraparte), gerencia, proceso, cargo Dueño, Custodio (si otra área lo administra), nombre, descripción y categoría. Al pulsar *Siguiente* se crea el borrador y se asigna el **ID** (`AI-RNSG-GTI-00012`), que no se puede modificar.
2. **Ubicación:** formato, ubicación, tipo de alojamiento. Si es nube o proveedor: tercero y país. Si es tecnológico: ID de la CMDB.
3. **Valoración C-I-D:** use la ayuda ⓘ de cada criterio. La aplicación muestra si el activo es crítico y el **nivel mínimo**; los niveles inferiores al mínimo aparecen en rojo y no se pueden enviar.
4. **Datos personales y terceros:** si hay datos personales, seleccione la actividad del **RAT**; indique si hay datos sensibles o transferencia internacional.
5. **Uso y retención:** revise las **reglas de manejo** del nivel (almacenamiento, transmisión, impresión, medios removibles, eliminación), indique cargos autorizados, período y fundamento de retención.

Puede **guardar como borrador** en cualquier paso. El panel de alertas indica qué falta.

## 4. Declarar y validar
* **Declarar** (solo el titular del cargo Dueño o su subrogante): marque la declaración y pulse *Enviar a validación*. Si hay alertas bloqueantes, el botón está deshabilitado y se indica el motivo.
* El **CISO** valida la consistencia; si hay datos personales, también el **DPO**. Si observan, recibirá el comentario por Outlook y Teams, el activo queda **Observado** y debe corregir y volver a declarar.
* Validado por todos → **Vigente**.

## 5. Ficha del activo
Pestañas por grupo de información, **Historial** (últimos cambios), **Evidencias** (listas de acceso, certificados, actas), **Relaciones** (dependencias) y **Excepciones**. Acciones disponibles según su rol y el estado:
* **Editar / Reclasificar:** si el activo está Vigente, el cambio de nivel exige **motivo** y vuelve a validación.
* **Traspasar:** a otro cargo; el titular del cargo receptor debe aceptar.
* **Dar de baja:** con el método que exige el nivel (Confidencial: destrucción segura y certificada; Reservado: destrucción segura con registro; Uso Interno: canales corporativos). Si la ejecuta un proveedor, el certificado es obligatorio. No se cierra sin él.
* **Solicitar excepción:** fundamento, riesgo, controles compensatorios y vigencia de **hasta 12 meses**. La evalúa el CISO (y el DPO si hay datos personales) y la autoriza el CSI.
* **Duplicar:** usa el activo como plantilla para uno similar.

## 6. Revisiones
* **Revisión integral:** en *Revisiones* verá la campaña del mes. Puede confirmar **"sin cambios" en lote** los activos que siguen iguales, o abrir y modificar los que cambiaron.
* **Revisión de accesos (Confidencial y Reservado):** adjunte la lista de accesos vigente (la entrega el Custodio), indique cuántos accesos retiró y los hallazgos.
* Si una revisión vence, se escala al CISO y a su jefatura.

## 7. Exportar
*Mis activos → Exportar* genera un Excel en su OneDrive con **solo los activos que usted puede ver**, etiquetado como **Reservado**. No lo reenvíe fuera de la organización.

## 8. Roles transversales
* **CISO:** bandeja de validación con vista comparativa; administración de maestros, parámetros, reasignaciones, reaperturas y carga masiva.
* **DPO:** bandeja de activos con datos personales o sensibles, sin RAT o con transferencia internacional, de ambas entidades.
* **Riesgos:** registra el ID de la matriz de riesgos de los activos críticos (*Registrar ID de riesgo*).
* **CSI:** autoriza excepciones (aprobación en Teams/Outlook) y consulta el tablero.
* **Auditoría Interna:** lectura de todo el inventario e historial.

## 9. Preguntas frecuentes
* *No veo un activo de otra gerencia.* Es lo esperado: solo ve los de su gerencia, los compartidos (*Ambas*) en que participa su gerencia, y todo si tiene un rol transversal.
* *Cambié un campo desde la lista de SharePoint y se revirtió.* Los campos calculados, de estado y de validación solo los modifica el sistema; los cambios de clasificación deben hacerse desde la app. El intento queda registrado.
* *Soy Delegado y no puedo declarar.* Solo el titular del cargo o su subrogante registrado puede hacerlo; su trabajo queda guardado.
