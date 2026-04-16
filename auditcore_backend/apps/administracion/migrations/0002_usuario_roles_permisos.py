from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('administracion', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='usuariointerno',
            name='documento_id',
            field=models.CharField(blank=True, max_length=30, help_text='Cédula o pasaporte'),
        ),
        migrations.AddField(
            model_name='usuariointerno',
            name='especialidad',
            field=models.CharField(blank=True, max_length=200, help_text='Área de expertise del auditor'),
        ),
        migrations.AddField(
            model_name='usuariointerno',
            name='tipo_contratacion',
            field=models.CharField(
                blank=True,
                choices=[('PLANTA', 'Planta'), ('CONTRATO', 'Contrato'), ('EXTERNO', 'Externo / Freelance')],
                default='PLANTA',
                max_length=10,
            ),
        ),
        migrations.AddField(
            model_name='usuariointerno',
            name='permisos_extra',
            field=models.JSONField(
                blank=True,
                default=list,
                help_text='Lista de permisos granulares adicionales al rol base',
            ),
        ),
        migrations.AlterField(
            model_name='usuariointerno',
            name='rol',
            field=models.CharField(
                choices=[
                    ('ADMIN', 'Administrador'),
                    ('AUDITOR_LIDER', 'Auditor Líder'),
                    ('AUDITOR_INTERNO', 'Auditor Interno'),
                    ('AUDITOR_EXTERNO', 'Auditor Externo'),
                    ('EJECUTIVO', 'Ejecutivo Comercial'),
                ],
                default='AUDITOR_INTERNO',
                max_length=20,
            ),
        ),
    ]
