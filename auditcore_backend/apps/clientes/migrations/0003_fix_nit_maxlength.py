from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('clientes', '0002_cliente_caracterizacion'),
    ]

    operations = [
        # nit estaba en max_length=20 (migración 0001) pero el modelo
        # define max_length=30. NITs colombianos con formato '900.123.456-7'
        # y cédulas largas necesitan los 30 chars.
        migrations.AlterField(
            model_name='cliente',
            name='nit',
            field=models.CharField(
                max_length=30,
                unique=True,
                help_text='NIT, RUT o documento tributario',
            ),
        ),
    ]
