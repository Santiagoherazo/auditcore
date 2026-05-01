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


    pass
