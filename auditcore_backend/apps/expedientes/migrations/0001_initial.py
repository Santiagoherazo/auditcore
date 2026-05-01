import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models

_EXPEDIENTE_FK = 'expedientes.expediente'


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('clientes', '0001_initial'),
        ('tipos_auditoria', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='Expediente',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('numero_expediente', models.CharField(editable=False, max_length=20, unique=True)),
                ('estado', models.CharField(choices=[('BORRADOR', 'Borrador'), ('ACTIVO', 'Activo'), ('EN_EJECUCION', 'En Ejecución'), ('COMPLETADO', 'Completado'), ('CANCELADO', 'Cancelado'), ('SUSPENDIDO', 'Suspendido')], default='BORRADOR', max_length=15)),
                ('tipo_origen', models.CharField(choices=[('NUEVO', 'Nuevo'), ('RENOVACION', 'Renovación'), ('SEGUIMIENTO', 'Seguimiento')], default='NUEVO', max_length=15)),
                ('fecha_apertura', models.DateField(auto_now_add=True)),
                ('fecha_estimada_cierre', models.DateField(blank=True, null=True)),
                ('fecha_cierre_real', models.DateField(blank=True, null=True)),
                ('porcentaje_avance', models.DecimalField(decimal_places=2, default=0, max_digits=5)),
                ('notas', models.TextField(blank=True)),
                ('metadata', models.JSONField(blank=True, default=dict)),
                ('fecha_creacion', models.DateTimeField(auto_now_add=True)),
                ('fecha_actualizacion', models.DateTimeField(auto_now=True)),
                ('auditor_lider', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='expedientes_lider', to=settings.AUTH_USER_MODEL)),
                ('cliente', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='expedientes', to='clientes.cliente')),
                ('ejecutivo', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='expedientes_ejecutivo', to=settings.AUTH_USER_MODEL)),
                ('expediente_origen', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='renovaciones', to=_EXPEDIENTE_FK)),
                ('tipo_auditoria', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, to='tipos_auditoria.tipoauditoria')),
            ],
            options={
                'db_table': 'expedientes',
                'ordering': ['-fecha_creacion'],
            },
        ),
        migrations.CreateModel(
            name='BitacoraExpediente',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('tipo_usuario', models.CharField(choices=[('INTERNO', 'Interno'), ('CLIENTE', 'Cliente'), ('SISTEMA', 'Sistema')], max_length=10)),
                ('accion', models.CharField(max_length=100)),
                ('descripcion', models.TextField()),
                ('entidad_afectada', models.CharField(blank=True, max_length=50)),
                ('metadata', models.JSONField(blank=True, default=dict)),
                ('fecha', models.DateTimeField(auto_now_add=True)),
                ('usuario_interno', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, to=settings.AUTH_USER_MODEL)),
                ('expediente', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='bitacora', to=_EXPEDIENTE_FK)),
            ],
            options={
                'db_table': 'bitacora_expediente',
                'ordering': ['-fecha'],
            },
        ),
        migrations.CreateModel(
            name='FaseExpediente',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('estado', models.CharField(choices=[('PENDIENTE', 'Pendiente'), ('EN_CURSO', 'En Curso'), ('COMPLETADA', 'Completada'), ('OMITIDA', 'Omitida')], default='PENDIENTE', max_length=12)),
                ('fecha_inicio', models.DateField(blank=True, null=True)),
                ('fecha_fin', models.DateField(blank=True, null=True)),
                ('observaciones', models.TextField(blank=True)),
                ('expediente', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='fases', to=_EXPEDIENTE_FK)),
                ('fase_tipo', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, to='tipos_auditoria.fasetipoauditoria')),
            ],
            options={
                'db_table': 'fases_expediente',
                'ordering': ['expediente', 'fase_tipo__orden'],
            },
        ),
        migrations.CreateModel(
            name='AsignacionEquipo',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('rol', models.CharField(choices=[('LIDER', 'Líder'), ('AUDITOR', 'Auditor'), ('APOYO', 'Apoyo'), ('REVISOR', 'Revisor')], max_length=10)),
                ('fecha_asignacion', models.DateField(auto_now_add=True)),
                ('activo', models.BooleanField(default=True)),
                ('usuario', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, to=settings.AUTH_USER_MODEL)),
                ('expediente', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='equipo', to=_EXPEDIENTE_FK)),
            ],
            options={
                'db_table': 'asignaciones_equipo',
                'unique_together': {('expediente', 'usuario')},
            },
        ),
    ]
