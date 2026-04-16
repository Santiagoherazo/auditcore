from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('administracion', '0002_usuario_roles_permisos'),
    ]

    operations = [
        migrations.AlterField(
            model_name='usuariointerno',
            name='rol',
            field=models.CharField(
                choices=[
                    ('SUPERVISOR', 'Supervisor'),
                    ('ASESOR',     'Asesor'),
                    ('AUDITOR',    'Auditor'),
                    ('AUXILIAR',   'Auxiliar'),
                    ('REVISOR',    'Revisor'),
                    ('CLIENTE',    'Cliente'),
                ],
                default='AUDITOR',
                max_length=12,
            ),
        ),
    ]
