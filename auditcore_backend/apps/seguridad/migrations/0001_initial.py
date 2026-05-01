import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='AuditLogSistema',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('tipo_usuario', models.CharField(choices=[('INTERNO', 'Interno'), ('CLIENTE', 'Cliente'), ('SISTEMA', 'Sistema')], default='INTERNO', max_length=10)),
                ('ip_origen', models.GenericIPAddressField(blank=True, null=True)),
                ('user_agent', models.CharField(blank=True, max_length=500)),
                ('accion', models.CharField(max_length=100)),
                ('recurso', models.CharField(blank=True, max_length=100)),
                ('recurso_id', models.CharField(blank=True, max_length=100)),
                ('resultado', models.CharField(choices=[('EXITOSO', 'Exitoso'), ('FALLIDO', 'Fallido'), ('DENEGADO', 'Denegado')], default='EXITOSO', max_length=10)),
                ('detalle', models.JSONField(blank=True, default=dict)),
                ('fecha', models.DateTimeField(auto_now_add=True)),
                ('usuario', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'audit_log_sistema',
                'ordering': ['-fecha'],
            },
        ),
    ]
