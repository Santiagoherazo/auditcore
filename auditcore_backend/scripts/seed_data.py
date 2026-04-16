"""
Script de datos iniciales (tipos de auditoría, fases y checklist).
Ejecutar UNA sola vez DESPUÉS de completar el wizard de instalación:
  python scripts/seed_data.py

NOTA: El superusuario administrador se crea mediante el wizard de instalación
en /setup — NO se crea aquí para evitar conflictos con el flujo de onboarding.
"""
import os, sys, django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from apps.tipos_auditoria.models import TipoAuditoria, FaseTipoAuditoria, ChecklistItem, DocumentoRequerido

# ── Tipos de auditoría ────────────────────────────────────────────────────
TIPOS = [
    {
        'codigo': 'ISO27001', 'nombre': 'ISO 27001 — Seguridad de la Información',
        'categoria': 'SEGURIDAD', 'nivel': 'AVANZADO', 'duracion': 60,
        'fases': ['Inicio y Planificación','Análisis de Riesgos','Evaluación de Controles','Informe y Certificación'],
        'checklist': [
            'Política de seguridad documentada y aprobada',
            'Inventario de activos de información actualizado',
            'Análisis de riesgos realizado en los últimos 12 meses',
            'Controles de acceso lógico implementados',
            'Plan de continuidad del negocio documentado',
        ],
        'docs': ['Política de Seguridad de la Información','Inventario de Activos','Registro de Riesgos','Plan de Continuidad'],
    },
    {
        'codigo': 'ISO9001', 'nombre': 'ISO 9001 — Gestión de Calidad',
        'categoria': 'CALIDAD', 'nivel': 'INTERMEDIO', 'duracion': 45,
        'fases': ['Revisión Documental','Auditoría en Campo','Verificación de Hallazgos','Certificación'],
        'checklist': [
            'Manual de calidad documentado',
            'Procesos de gestión de proveedores definidos',
            'Indicadores de desempeño establecidos y medidos',
            'Acciones correctivas documentadas',
            'Revisión por la dirección realizada',
        ],
        'docs': ['Manual de Calidad','Mapa de Procesos','Registros de No Conformidades','Informes de Auditoría Interna'],
    },
    {
        'codigo': 'SOC2', 'nombre': 'SOC 2 Tipo II — Controles de Servicio',
        'categoria': 'SEGURIDAD', 'nivel': 'AVANZADO', 'duracion': 90,
        'fases': ['Definición de Alcance','Período de Observación','Pruebas de Controles','Informe Final'],
        'checklist': [
            'Controles de disponibilidad del servicio documentados',
            'Controles de confidencialidad implementados',
            'Monitoreo de seguridad activo',
            'Gestión de acceso privilegiado documentada',
            'Pruebas de penetración realizadas en el período',
        ],
        'docs': ['Descripción del Sistema','Políticas de Seguridad','Evidencias de Controles','Resultados de Pruebas'],
    },
    {
        'codigo': 'ISO45001', 'nombre': 'ISO 45001 — Seguridad y Salud Ocupacional',
        'categoria': 'AMBIENTAL', 'nivel': 'INTERMEDIO', 'duracion': 30,
        'fases': ['Revisión Inicial','Evaluación de Riesgos','Verificación de Cumplimiento','Certificación'],
        'checklist': [
            'Política de seguridad y salud ocupacional aprobada',
            'Identificación de peligros y evaluación de riesgos',
            'Programa de capacitación en seguridad implementado',
            'Registros de accidentes e incidentes actualizados',
            'Comité paritario de seguridad activo',
        ],
        'docs': ['Política SSO','Matriz de Riesgos Laborales','Registros de Capacitación','Estadísticas de Accidentalidad'],
    },
    {
        'codigo': 'COBIT', 'nombre': 'COBIT 2019 — Gobernanza de TI',
        'categoria': 'FINANCIERO', 'nivel': 'AVANZADO', 'duracion': 75,
        'fases': ['Evaluación de Madurez','Análisis de Brechas','Verificación de Procesos','Informe Ejecutivo'],
        'checklist': [
            'Marco de gobernanza de TI definido y documentado',
            'Gestión de proyectos de TI estructurada',
            'Gestión de riesgos de TI integrada',
            'Métricas de desempeño de TI establecidas',
            'Gestión de proveedores de TI documentada',
        ],
        'docs': ['Marco de Gobernanza TI','Inventario de Aplicaciones','Políticas de TI','Informes de Desempeño TI'],
    },
]

for t_data in TIPOS:
    tipo, creado = TipoAuditoria.objects.get_or_create(
        codigo=t_data['codigo'],
        defaults={
            'nombre': t_data['nombre'], 'categoria': t_data['categoria'],
            'nivel': t_data['nivel'], 'duracion_estimada_dias': t_data['duracion'],
        }
    )
    if creado:
        for i, fase_nombre in enumerate(t_data['fases'], 1):
            FaseTipoAuditoria.objects.create(
                tipo_auditoria=tipo, nombre=fase_nombre, orden=i,
                duracion_estimada_dias=t_data['duracion'] // len(t_data['fases']),
                es_fase_final=(i == len(t_data['fases'])),
            )
        for i, desc in enumerate(t_data['checklist'], 1):
            ChecklistItem.objects.create(
                tipo_auditoria=tipo, codigo=f'{tipo.codigo}-{i:02d}',
                descripcion=desc, orden=i, obligatorio=True,
            )
        for i, nombre_doc in enumerate(t_data['docs'], 1):
            DocumentoRequerido.objects.create(
                tipo_auditoria=tipo, nombre=nombre_doc, orden=i, obligatorio=True,
            )
        print(f'✅ Tipo creado: {tipo.codigo} — {tipo.nombre}')
    else:
        print(f'ℹ️  Ya existe: {tipo.codigo}')

print('\n🎉 Datos iniciales cargados. Puedes iniciar sesión en:')
print('   API:    http://localhost:8000/api/docs/')
print('   Admin:  http://localhost:8000/admin/')
print('   Email:  admin@auditcore.com')
print('   Pass:   Admin1234!')