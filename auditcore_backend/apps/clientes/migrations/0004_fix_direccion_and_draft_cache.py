"""
0004_fix_direccion_and_draft_cache
===================================
Problemas que resuelve
-----------------------
1. La migración 0001_initial creó una columna `direccion` (NOT NULL) en la
   tabla `clientes`. La refactorización 0002 introdujo `direccion_principal`
   (blank=True) y nunca eliminó la columna original. Postgres sigue exigiendo
   un valor en cada INSERT → IntegrityError en el Paso 1 del formulario
   multi-paso porque el usuario aún no llegó a la sección de Ubicación.

2. SedeCliente.direccion tampoco tenía blank=True, lo que causaría el mismo
   error al crear sedes sin dirección desde el formulario.
"""
from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('clientes', '0003_fix_nit_maxlength'),
    ]

    operations = [
        # ── Fix 1: eliminar columna `direccion` fantasma de la tabla clientes ──
        migrations.RunSQL(
            sql="""
                ALTER TABLE clientes
                DROP COLUMN IF EXISTS direccion;
            """,
            reverse_sql="""
                ALTER TABLE clientes
                ADD COLUMN IF NOT EXISTS direccion VARCHAR(255) NOT NULL DEFAULT '';
            """,
        ),

        # ── Fix 2: hacer SedeCliente.direccion opcional (blank=True) ──────────
        migrations.RunSQL(
            sql="""
                ALTER TABLE sedes_cliente
                ALTER COLUMN direccion SET DEFAULT '';
                UPDATE sedes_cliente SET direccion = '' WHERE direccion IS NULL;
                ALTER TABLE sedes_cliente
                ALTER COLUMN direccion DROP NOT NULL;
            """,
            reverse_sql="""
                UPDATE sedes_cliente SET direccion = 'Sin dirección' WHERE direccion = '' OR direccion IS NULL;
                ALTER TABLE sedes_cliente
                ALTER COLUMN direccion SET NOT NULL;
                ALTER TABLE sedes_cliente
                ALTER COLUMN direccion DROP DEFAULT;
            """,
        ),
    ]
