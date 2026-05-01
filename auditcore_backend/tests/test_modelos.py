import os
import pytest
from django.test import TestCase
from django.utils import timezone


_TEST_PWD       = os.environ.get('TEST_USER_SECRET',  'Test1234!')
_TEST_PWD_ADMIN = os.environ.get('TEST_ADMIN_SECRET', 'Admin1234!')


@pytest.mark.django_db
class TestUsuarioInterno(TestCase):
    def test_crear_usuario_interno(self):
        from apps.administracion.models import UsuarioInterno
        u = UsuarioInterno.objects.create_user(
            email='test@auditcore.com',
            password=_TEST_PWD,
            nombre='Juan',
            apellido='Pérez',
            rol='AUDITOR',
        )
        assert u.email == 'test@auditcore.com'
        assert u.nombre_completo == 'Juan Pérez'
        assert u.check_password(_TEST_PWD)
        assert u.estado == 'ACTIVO'
        assert u.intentos_fallidos == 0

    def test_bloqueo_tras_intentos(self):
        from apps.administracion.models import UsuarioInterno
        from apps.administracion.mfa import registrar_intento_fallido, verificar_bloqueo
        u = UsuarioInterno.objects.create_user(
            email='bloqueo@auditcore.com', password=_TEST_PWD,
            nombre='Test', apellido='Bloqueo',
        )
        for _ in range(5):
            registrar_intento_fallido(u)
            u.refresh_from_db()
        assert u.estado == 'BLOQUEADO'
        assert verificar_bloqueo(u) is True


@pytest.mark.django_db
class TestCliente(TestCase):
    def test_crear_cliente(self):
        from apps.administracion.models import UsuarioInterno
        from apps.clientes.models import Cliente
        admin = UsuarioInterno.objects.create_user(
            email='admin@test.com', password=_TEST_PWD_ADMIN,
            nombre='Admin', apellido='Test', rol='ADMIN',
        )
        c = Cliente.objects.create(
            razon_social='Empresa Test S.A.S.',
            nit='900123456-1',
            sector='TECNOLOGIA',
            creado_por=admin,
        )
        assert str(c.nit) == '900123456-1'
        assert c.estado == 'PROSPECTO'

    def test_nit_unico(self):
        from apps.administracion.models import UsuarioInterno
        from apps.clientes.models import Cliente
        from django.db import IntegrityError
        admin = UsuarioInterno.objects.create_user(
            email='admin2@test.com', password=_TEST_PWD_ADMIN,
            nombre='Admin', apellido='Test', rol='ADMIN',
        )
        Cliente.objects.create(razon_social='Empresa A', nit='111', creado_por=admin)
        with pytest.raises(IntegrityError):
            Cliente.objects.create(razon_social='Empresa B', nit='111', creado_por=admin)


@pytest.mark.django_db
class TestExpediente(TestCase):
    fixtures = []

    def _crear_base(self):
        from apps.administracion.models import UsuarioInterno
        from apps.clientes.models import Cliente
        from apps.tipos_auditoria.models import TipoAuditoria
        admin = UsuarioInterno.objects.create_user(
            email='lider@test.com', password=_TEST_PWD,
            nombre='Lider', apellido='Test', rol='AUDITOR_LIDER',
        )
        cliente = Cliente.objects.create(
            razon_social='Cliente Test', nit='555', creado_por=admin
        )
        tipo = TipoAuditoria.objects.create(
            codigo='ISO-9001', nombre='ISO 9001', nivel='INTERMEDIO',
            duracion_estimada_dias=30,
        )
        return admin, cliente, tipo

    def test_numero_auto_generado(self):
        from apps.expedientes.models import Expediente
        admin, cliente, tipo = self._crear_base()
        exp = Expediente.objects.create(
            cliente=cliente,
            tipo_auditoria=tipo,
            auditor_lider=admin,
        )
        assert exp.numero_expediente.startswith('EXP-')
        year = timezone.now().year
        assert str(year) in exp.numero_expediente

    def test_bitacora_inmutable(self):
        from apps.expedientes.models import Expediente, BitacoraExpediente
        admin, cliente, tipo = self._crear_base()
        exp = Expediente.objects.create(
            cliente=cliente, tipo_auditoria=tipo, auditor_lider=admin,
        )
        entrada = BitacoraExpediente.registrar(
            expediente=exp, accion='TEST', descripcion='Prueba'
        )
        with pytest.raises(ValueError):
            entrada.descripcion = 'Modificado'
            entrada.save()
        with pytest.raises(ValueError):
            entrada.delete()