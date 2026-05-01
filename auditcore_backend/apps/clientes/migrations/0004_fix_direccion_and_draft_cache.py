from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('clientes', '0003_fix_nit_maxlength'),
    ]

    operations = [

        migrations.RunSQL(
            sql="""
                ALTER TABLE clientes
                DROP COLUMN IF EXISTS direccion;


,
        ),


        migrations.RunSQL(
            sql="""
                ALTER TABLE sedes_cliente
                ALTER COLUMN direccion SET DEFAULT '';
                UPDATE sedes_cliente SET direccion = '' WHERE direccion IS NULL;
                ALTER TABLE sedes_cliente
                ALTER COLUMN direccion DROP NOT NULL;


,
        ),
    ]
