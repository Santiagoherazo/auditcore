import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('tipos_auditoria', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='EsquemaFormulario',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('nombre', models.CharField(max_length=200)),
                ('contexto', models.CharField(choices=[('EXPEDIENTE', 'Expediente'), ('HALLAZGO', 'Hallazgo'), ('DOCUMENTO', 'Documento'), ('CLIENTE', 'Cliente')], max_length=15)),
                ('version', models.PositiveIntegerField(default=1)),
                ('activo', models.BooleanField(default=True)),
                ('fecha_creacion', models.DateTimeField(auto_now_add=True)),
                ('tipo_auditoria', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, to='tipos_auditoria.tipoauditoria')),
            ],
            options={
                'db_table': 'esquemas_formulario',
            },
        ),
        migrations.CreateModel(
            name='CampoFormulario',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('nombre', models.CharField(max_length=100)),
                ('etiqueta', models.CharField(max_length=200)),
                ('tipo', models.CharField(choices=[('TEXTO', 'Texto'), ('NUMERO', 'Número'), ('FECHA', 'Fecha'), ('LISTA', 'Lista de opciones'), ('BOOLEANO', 'Sí / No'), ('ARCHIVO', 'Archivo')], max_length=10)),
                ('obligatorio', models.BooleanField(default=False)),
                ('orden', models.PositiveIntegerField(default=0)),
                ('opciones', models.JSONField(blank=True, default=list)),
                ('validaciones', models.JSONField(blank=True, default=dict)),
                ('activo', models.BooleanField(default=True)),
                ('esquema', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='campos', to='formularios.esquemaformulario')),
            ],
            options={
                'db_table': 'campos_formulario',
                'ordering': ['esquema', 'orden'],
            },
        ),
        migrations.CreateModel(
            name='ValorFormulario',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('entidad_tipo', models.CharField(max_length=50)),
                ('entidad_id', models.UUIDField()),
                ('valores', models.JSONField(default=dict)),
                ('fecha_creacion', models.DateTimeField(auto_now_add=True)),
                ('fecha_actualizacion', models.DateTimeField(auto_now=True)),
                ('creado_por', models.ForeignKey(null=True, on_delete=django.db.models.deletion.PROTECT, to=settings.AUTH_USER_MODEL)),
                ('esquema', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, to='formularios.esquemaformulario')),
            ],
            options={
                'db_table': 'valores_formulario',
                'indexes': [models.Index(fields=['entidad_tipo', 'entidad_id'], name='valores_for_entidad_c194a5_idx')],
            },
        ),
    ]
