from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('formularios', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='esquemaformulario',
            name='descripcion',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='esquemaformulario',
            name='origen',
            field=models.CharField(
                choices=[
                    ('MANUAL', 'Creado manualmente'),
                    ('BOT_PDF', 'Importado desde PDF via bot'),
                    ('BOT_WORD', 'Importado desde Word via bot'),
                    ('BOT_EXCEL', 'Importado desde Excel via bot'),
                ],
                default='MANUAL',
                max_length=10,
            ),
        ),
        migrations.AddField(
            model_name='esquemaformulario',
            name='creado_por',
            field=models.ForeignKey(
                blank=True, null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='formularios_creados',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name='esquemaformulario',
            name='fecha_actualizacion',
            field=models.DateTimeField(auto_now=True),
        ),
        migrations.AddField(
            model_name='campoformulario',
            name='ayuda',
            field=models.CharField(blank=True, help_text='Texto de ayuda visible al auditor', max_length=300),
        ),
        migrations.AlterField(
            model_name='campoformulario',
            name='tipo',
            field=models.CharField(
                choices=[
                    ('TEXTO', 'Texto libre'), ('NUMERO', 'Número'), ('FECHA', 'Fecha'),
                    ('LISTA', 'Lista de opciones'), ('BOOLEANO', 'Sí / No'),
                    ('ARCHIVO', 'Archivo adjunto'), ('FIRMA', 'Firma'), ('TABLA', 'Tabla de datos'),
                ],
                max_length=10,
            ),
        ),
    ]
