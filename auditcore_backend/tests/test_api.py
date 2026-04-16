"""
tests/test_api.py
AC-70: Tests de integración de la API REST
"""
import pytest
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status


@pytest.mark.django_db
class TestAuthAPI(TestCase):
    def setUp(self):
        from apps.administracion.models import UsuarioInterno
        self.user = UsuarioInterno.objects.create_user(
            email='apitest@auditcore.com',
            password='Test1234!',
            nombre='API', apellido='Test', rol='ADMIN',
        )
        self.client = APIClient()

    def test_login_exitoso(self):
        res = self.client.post('/api/auth/login/', {
            'email': 'apitest@auditcore.com',
            'password': 'Test1234!',
        }, format='json')
        assert res.status_code == status.HTTP_200_OK
        assert 'access' in res.data
        assert 'refresh' in res.data

    def test_login_credenciales_invalidas(self):
        res = self.client.post('/api/auth/login/', {
            'email': 'apitest@auditcore.com',
            'password': 'WrongPassword',
        }, format='json')
        assert res.status_code == status.HTTP_401_UNAUTHORIZED

    def test_login_bloqueo_tras_5_intentos(self):
        for _ in range(5):
            self.client.post('/api/auth/login/', {
                'email': 'apitest@auditcore.com',
                'password': 'WrongPassword',
            }, format='json')
        self.user.refresh_from_db()
        assert self.user.estado == 'BLOQUEADO'

    def test_endpoint_protegido_sin_token(self):
        res = self.client.get('/api/clientes/')
        assert res.status_code == status.HTTP_401_UNAUTHORIZED

    def test_endpoint_protegido_con_token(self):
        login = self.client.post('/api/auth/login/', {
            'email': 'apitest@auditcore.com', 'password': 'Test1234!',
        }, format='json')
        token = login.data['access']
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        res = self.client.get('/api/clientes/')
        assert res.status_code == status.HTTP_200_OK


@pytest.mark.django_db
class TestClientesAPI(TestCase):
    def setUp(self):
        from apps.administracion.models import UsuarioInterno
        self.user = UsuarioInterno.objects.create_user(
            email='admin@test.com', password='Admin1234!',
            nombre='Admin', apellido='Test', rol='ADMIN',
        )
        self.client = APIClient()
        login = self.client.post('/api/auth/login/', {
            'email': 'admin@test.com', 'password': 'Admin1234!',
        }, format='json')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {login.data["access"]}')

    def test_crear_cliente(self):
        res = self.client.post('/api/clientes/', {
            'razon_social': 'Empresa Test',
            'nit': '900-PYTEST-1',
            'sector': 'TECNOLOGIA',
        }, format='json')
        assert res.status_code == status.HTTP_201_CREATED
        assert res.data['nit'] == '900-PYTEST-1'

    def test_listar_clientes(self):
        res = self.client.get('/api/clientes/')
        assert res.status_code == status.HTTP_200_OK
        assert 'results' in res.data

    def test_nit_duplicado_error(self):
        self.client.post('/api/clientes/', {'razon_social': 'A', 'nit': 'DUP-001', 'sector': 'OTRO'}, format='json')
        res = self.client.post('/api/clientes/', {'razon_social': 'B', 'nit': 'DUP-001', 'sector': 'OTRO'}, format='json')
        assert res.status_code == status.HTTP_400_BAD_REQUEST


@pytest.mark.django_db
class TestVerificacionCertificado(TestCase):
    """Test del endpoint público de verificación."""
    def setUp(self):
        self.client = APIClient()

    def test_codigo_inexistente(self):
        res = self.client.get('/api/certificaciones/verificar/?codigo=NOEXISTE')
        assert res.status_code == status.HTTP_200_OK
        assert res.data.get('valido') is False