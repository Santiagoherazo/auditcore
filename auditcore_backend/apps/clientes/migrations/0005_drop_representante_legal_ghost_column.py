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


,
        ),
    ]
