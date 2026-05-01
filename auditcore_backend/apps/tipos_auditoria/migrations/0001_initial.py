import django.db.models.deletion
import uuid
from django.db import migrations, models

_TIPO_AUDITORIA_FK = 'tipos_auditoria.tipoauditoria'


class Migration(migrations.Migration):

    initial = True

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='TipoAuditoria',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('codigo', models.CharField(max_length=20, unique=True)),
                ('nombre', models.CharField(max_length=200)),
                ('descripcion', models.TextField(blank=True)),
                ('categoria', models.CharField(choices=[('SEGURIDAD', 'Seguridad'), ('CALIDAD', 'Calidad'), ('AMBIENTAL', 'Ambiental'), ('FINANCIERO', 'Financiero'), ('OTRO', 'Otro')], default='OTRO', max_length=20)),
                ('nivel', models.CharField(choices=[('BASICO', 'Básico'), ('INTERMEDIO', 'Intermedio'), ('AVANZADO', 'Avanzado')], default='BASICO', max_length=15)),
                ('certificacion_tipo', models.CharField(choices=[('PROPIA', 'Propia'), ('EXTERNA', 'Externa'), ('AMBAS', 'Ambas')], default='PROPIA', max_length=10)),
                ('duracion_estimada_dias', models.PositiveIntegerField(default=30)),
                ('version', models.CharField(default='1.0', max_length=10)),
                ('activo', models.BooleanField(default=True)),
                ('fecha_creacion', models.DateTimeField(auto_now_add=True)),
            ],
            options={
                'db_table': 'tipos_auditoria',
                'ordering': ['nombre'],
            },
        ),
        migrations.CreateModel(
            name='FaseTipoAuditoria',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('nombre', models.CharField(max_length=100)),
                ('descripcion', models.TextField(blank=True)),
                ('orden', models.PositiveIntegerField()),
                ('duracion_estimada_dias', models.PositiveIntegerField(default=7)),
                ('es_fase_final', models.BooleanField(default=False)),
                ('tipo_auditoria', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='fases', to=_TIPO_AUDITORIA_FK)),
            ],
            options={
                'db_table': 'fases_tipo_auditoria',
                'ordering': ['tipo_auditoria', 'orden'],
            },
        ),
        migrations.CreateModel(
            name='DocumentoRequerido',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('nombre', models.CharField(max_length=200)),
                ('descripcion', models.TextField(blank=True)),
                ('obligatorio', models.BooleanField(default=True)),
                ('orden', models.PositiveIntegerField(default=0)),
                ('tipo_auditoria', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='documentos_requeridos', to=_TIPO_AUDITORIA_FK)),
            ],
            options={
                'db_table': 'documentos_requeridos',
                'ordering': ['tipo_auditoria', 'orden'],
            },
        ),
        migrations.CreateModel(
            name='ChecklistItem',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('codigo', models.CharField(max_length=20)),
                ('descripcion', models.TextField()),
                ('categoria', models.CharField(choices=[('DOCUMENTAL', 'Documental'), ('TECNICO', 'Técnico'), ('LEGAL', 'Legal'), ('OPERACIONAL', 'Operacional')], default='DOCUMENTAL', max_length=15)),
                ('obligatorio', models.BooleanField(default=True)),
                ('orden', models.PositiveIntegerField(default=0)),
                ('fase', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='items', to='tipos_auditoria.fasetipoauditoria')),
                ('tipo_auditoria', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='checklist_items', to=_TIPO_AUDITORIA_FK)),
            ],
            options={
                'db_table': 'checklist_items',
                'ordering': ['tipo_auditoria', 'orden'],
            },
        ),
    ]
