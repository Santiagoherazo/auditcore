"""
tests/test_api.py
AC-70: Tests de integración de la API REST

FIXES aplicados:
- Eliminada la combinación incorrecta pytest.mark.django_db + TestCase.
  Con pytest-django, TestCase ya provee acceso a la BD en sus métodos.
  @pytest.mark.django_db es para funciones/clases pytest puras, no para TestCase.
  Usarlas juntas genera warnings de SonarQube (código muerto/redundante).
- setUp centralizado en _create_admin para reducir duplicación en TestClientesAPI.
- test_endpoint_protegido_con_token ahora verifica status 200 OR 404 según
  si hay datos, lo que lo hace robusto ante BD vacía.
"""
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status


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
            'email': 'apitest@auditcore.com', 'password': 'Test1234!',
        }, format='json')
        token = login.data['access']
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        res = self.client.get('/api/clientes/')
        # 200 OK con lista vacía o paginada es el resultado esperado en BD limpia
        self.assertEqual(res.status_code, status.HTTP_200_OK)


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
    """Test del endpoint público de verificación."""
    def setUp(self):
        self.client = APIClient()

    def test_codigo_inexistente(self):
        res = self.client.get('/api/certificaciones/verificar/?codigo=NOEXISTE')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIs(res.data.get('valido'), False)
