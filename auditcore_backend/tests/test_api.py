from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
import os


_TEST_PWD_AUTH  = os.environ.get('TEST_AUTH_SECRET',  'Test1234!')
_TEST_PWD_ADMIN = os.environ.get('TEST_ADMIN_SECRET', 'Admin1234!')


class TestAuthAPI(TestCase):
    def setUp(self):
        from apps.administracion.models import UsuarioInterno
        self.user = UsuarioInterno.objects.create_user(
            email='apitest@auditcore.com',
            password=_TEST_PWD_AUTH,
            nombre='API', apellido='Test', rol='ADMIN',
        )
        self.client = APIClient()

    def test_login_exitoso(self):
        res = self.client.post('/api/auth/login/', {
            'email': 'apitest@auditcore.com',
            'password': _TEST_PWD_AUTH,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('access', res.data)
        self.assertIn('refresh', res.data)

    def test_login_credenciales_invalidas(self):
        res = self.client.post('/api/auth/login/', {
            'email': 'apitest@auditcore.com',
            'password': 'WrongPassword',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_bloqueo_tras_5_intentos(self):
        for _ in range(5):
            self.client.post('/api/auth/login/', {
                'email': 'apitest@auditcore.com',
                'password': 'WrongPassword',
            }, format='json')
        self.user.refresh_from_db()
        self.assertEqual(self.user.estado, 'BLOQUEADO')

    def test_endpoint_protegido_sin_token(self):
        res = self.client.get('/api/clientes/')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_endpoint_protegido_con_token(self):
        login = self.client.post('/api/auth/login/', {
            'email': 'apitest@auditcore.com', 'password': _TEST_PWD_AUTH,
        }, format='json')
        token = login.data['access']
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        res = self.client.get('/api/clientes/')

        self.assertEqual(res.status_code, status.HTTP_200_OK)


class TestClientesAPI(TestCase):
    def setUp(self):
        from apps.administracion.models import UsuarioInterno
        self.user = UsuarioInterno.objects.create_user(
            email='admin@test.com', password=_TEST_PWD_ADMIN,
            nombre='Admin', apellido='Test', rol='ADMIN',
        )
        self.client = APIClient()
        login = self.client.post('/api/auth/login/', {
            'email': 'admin@test.com', 'password': _TEST_PWD_ADMIN,
        }, format='json')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {login.data["access"]}')

    def test_crear_cliente(self):
        res = self.client.post('/api/clientes/', {
            'razon_social': 'Empresa Test',
            'nit': '900-PYTEST-1',
            'sector': 'TECNOLOGIA',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['nit'], '900-PYTEST-1')

    def test_listar_clientes(self):
        res = self.client.get('/api/clientes/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('results', res.data)

    def test_nit_duplicado_error(self):
        self.client.post('/api/clientes/', {
            'razon_social': 'A', 'nit': 'DUP-001', 'sector': 'OTRO',
        }, format='json')
        res = self.client.post('/api/clientes/', {
            'razon_social': 'B', 'nit': 'DUP-001', 'sector': 'OTRO',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)


class TestVerificacionCertificado(TestCase):

    def setUp(self):
        self.client = APIClient()

    def test_codigo_inexistente(self):
        res = self.client.get('/api/certificaciones/verificar/?codigo=NOEXISTE')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIs(res.data.get('valido'), False)
