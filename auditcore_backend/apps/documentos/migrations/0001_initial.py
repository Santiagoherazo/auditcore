import apps.documentos.models
import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('expedientes', '0001_initial'),
        ('tipos_auditoria', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='DocumentoExpediente',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('nombre', models.CharField(max_length=255)),
                ('archivo', models.FileField(blank=True, null=True, upload_to=apps.documentos.models.doc_upload_path)),
                ('hash_sha256', models.CharField(blank=True, max_length=64)),
                ('estado', models.CharField(choices=[('PENDIENTE', 'Pendiente'), ('RECIBIDO', 'Recibido'), ('APROBADO', 'Aprobado'), ('RECHAZADO', 'Rechazado'), ('VENCIDO', 'Vencido')], default='PENDIENTE', max_length=10)),
                ('version', models.PositiveIntegerField(default=1)),
                ('fecha_revision', models.DateTimeField(blank=True, null=True)),
                ('observacion_revision', models.TextField(blank=True)),
                ('fecha_subida', models.DateTimeField(auto_now_add=True)),
                ('documento_requerido', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, to='tipos_auditoria.documentorequerido')),
                ('expediente', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='documentos', to='expedientes.expediente')),
                ('revisado_por', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='documentos_revisados', to=settings.AUTH_USER_MODEL)),
                ('subido_por', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='documentos_subidos', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'documentos_expediente',
                'ordering': ['expediente', 'nombre', '-version'],
            },
        ),
    ]
