from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('clientes', '0002_cliente_caracterizacion'),
    ]

    operations = [


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
