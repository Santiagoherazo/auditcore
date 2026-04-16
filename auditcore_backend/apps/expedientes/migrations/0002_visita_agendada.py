import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('expedientes', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='VisitaAgendada',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('tipo', models.CharField(
                    choices=[
                        ('APERTURA', 'Reunión de apertura'),
                        ('CAMPO', 'Visita en campo'),
                        ('DOCUMENTACION', 'Revisión de documentación'),
                        ('SEGUIMIENTO', 'Seguimiento de hallazgos'),
                        ('CIERRE', 'Reunión de cierre'),
                        ('OTRO', 'Otro'),
                    ],
                    default='CAMPO', max_length=15,
                )),
                ('titulo', models.CharField(max_length=200)),
                ('descripcion', models.TextField(blank=True)),
                ('fecha_inicio', models.DateTimeField()),
                ('fecha_fin', models.DateTimeField()),
                ('lugar', models.CharField(blank=True, max_length=300)),
                ('estado', models.CharField(
                    choices=[
                        ('PROGRAMADA', 'Programada'),
                        ('CONFIRMADA', 'Confirmada'),
                        ('REALIZADA', 'Realizada'),
                        ('REPROGRAMADA', 'Reprogramada'),
                        ('CANCELADA', 'Cancelada'),
                    ],
                    default='PROGRAMADA', max_length=12,
                )),
                ('notas_resultado', models.TextField(blank=True)),
                ('fecha_creacion', models.DateTimeField(auto_now_add=True)),
                ('fecha_actualizacion', models.DateTimeField(auto_now=True)),
                ('expediente', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='visitas',
                    to='expedientes.expediente',
                )),
                ('fase', models.ForeignKey(
                    blank=True, null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='visitas',
                    to='expedientes.faseexpediente',
                )),
                ('creado_por', models.ForeignKey(
                    null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='visitas_creadas',
                    to=settings.AUTH_USER_MODEL,
                )),
                ('participantes', models.ManyToManyField(
                    blank=True,
                    related_name='visitas_asignadas',
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={'db_table': 'visitas_agendadas', 'ordering': ['fecha_inicio']},
        ),
    ]
