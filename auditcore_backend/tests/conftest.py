import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')

if 'DATABASE_URL' not in os.environ:
    os.environ.setdefault(
        'DATABASE_URL',
        'postgres://auditcore_user:auditcore2026@localhost:5432/auditcore'
    )

import pytest


@pytest.fixture(autouse=True)
def habilitar_acceso_db(db):
    """
    Activa el acceso a la base de datos para todos los tests automáticamente.
    FIX: el nombre original 'reset_db_sequences' era engañoso — no reseteaba
    nada, solo activaba el fixture 'db' de pytest-django. Renombrado para
    reflejar su comportamiento real.
    """
    pass
