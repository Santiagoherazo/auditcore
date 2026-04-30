"""
0005_drop_representante_legal_ghost_column
==========================================
Problema que resuelve
----------------------
La migración 0001_initial creó la columna `representante_legal` (VARCHAR 200,
NOT NULL) en la tabla `clientes`. La refactorización 0002 introdujo los
campos granulares `rep_legal_nombre`, `rep_legal_documento`, `rep_legal_tipo_doc`,
`rep_legal_cargo`, `rep_legal_email` y `rep_legal_telefono`, pero **nunca
eliminó** la columna original.

El modelo actual (models.py) ya no declara `representante_legal`, por lo que
Django no incluye ese campo en el INSERT. PostgreSQL intenta insertar NULL
en una columna NOT NULL → IntegrityError en el paso 6 (Contacto Operativo)
del formulario multi-paso de creación de cliente:

    error: null value in column "representante_legal" of relation "clientes"
           violates not-null constraint

Solución
--------
Eliminar la columna fantasma. Ya no forma parte del modelo y su eliminación
es segura: todos los datos útiles del representante legal se almacenan en los
campos `rep_legal_*` desde la migración 0002.
"""
from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('clientes', '0004_fix_direccion_and_draft_cache'),
    ]

    operations = [
        migrations.RunSQL(
            sql="""
                ALTER TABLE clientes
                DROP COLUMN IF EXISTS representante_legal;
            """,
            reverse_sql="""
                ALTER TABLE clientes
                ADD COLUMN IF NOT EXISTS representante_legal VARCHAR(200) NOT NULL DEFAULT '';
            """,
        ),
    ]
