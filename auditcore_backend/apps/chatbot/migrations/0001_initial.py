import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('clientes', '0001_initial'),
        ('expedientes', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='Conversacion',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('canal', models.CharField(choices=[('WEB', 'Web'), ('MOVIL', 'Móvil'), ('INTERNO', 'Interno')], default='WEB', max_length=8)),
                ('estado', models.CharField(choices=[('ACTIVA', 'Activa'), ('ARCHIVADA', 'Archivada')], default='ACTIVA', max_length=10)),
                ('fecha_creacion', models.DateTimeField(auto_now_add=True)),
                ('fecha_actualizacion', models.DateTimeField(auto_now=True)),
                ('cliente', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='conversaciones', to='clientes.cliente')),
                ('expediente', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='conversaciones', to='expedientes.expediente')),
                ('usuario_interno', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='conversaciones', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'conversaciones',
                'ordering': ['-fecha_actualizacion'],
            },
        ),
        migrations.CreateModel(
            name='MensajeConversacion',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('rol', models.CharField(choices=[('USUARIO', 'Usuario'), ('ASISTENTE', 'Asistente'), ('SISTEMA', 'Sistema')], max_length=10)),
                ('contenido', models.TextField()),
                ('tokens_usados', models.PositiveIntegerField(default=0)),
                ('metadata', models.JSONField(blank=True, default=dict)),
                ('fecha', models.DateTimeField(auto_now_add=True)),
                ('conversacion', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='mensajes', to='chatbot.conversacion')),
            ],
            options={
                'db_table': 'mensajes_conversacion',
                'ordering': ['conversacion', 'fecha'],
            },
        ),
    ]
