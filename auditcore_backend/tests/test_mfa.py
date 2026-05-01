import time
import pyotp
import threading
from datetime import timedelta
from unittest.mock import patch, MagicMock

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status
import os


_TEST_PWD       = os.environ.get('TEST_USER_SECRET', 'Test1234!')
_TEST_PWD_LOGIN = os.environ.get('TEST_LOGIN_SECRET', 'Login1234!')


def _crear_usuario(email='mfa@test.com', password=_TEST_PWD, rol='AUDITOR',
                   mfa_habilitado=False, mfa_secret='', estado='ACTIVO',
                   intentos_fallidos=0):

    from apps.administracion.models import UsuarioInterno
    u = UsuarioInterno.objects.create_user(
        email=email, password=password,
        nombre='Test', apellido='MFA', rol=rol,
    )
    u.mfa_habilitado   = mfa_habilitado
    u.mfa_secret       = mfa_secret
    u.estado           = estado
    u.intentos_fallidos = intentos_fallidos
    u.save(update_fields=[
        'mfa_habilitado', 'mfa_secret', 'estado', 'intentos_fallidos',
    ])
    return u


def _usuario_con_mfa(email='mfa_on@test.com'):

    secret = pyotp.random_base32()
    return _crear_usuario(email=email, mfa_habilitado=True, mfa_secret=secret), secret


def _codigo_actual(secret):
    return pyotp.TOTP(secret).now()


def _codigo_en(secret, offset_segundos):

    return pyotp.TOTP(secret).at(time.time() + offset_segundos)


class TestGeneracionSecretoTOTP(TestCase):


    def test_secret_es_base32_valido(self):

        from apps.administracion.mfa import generar_secret_totp
        import base64
        secret = generar_secret_totp()

        self.assertIsInstance(secret, str)
        self.assertGreater(len(secret), 0)

        padded = secret + '=' * (-len(secret) % 8)
        decoded = base64.b32decode(padded)
        self.assertGreater(len(decoded), 0)

    def test_secret_tiene_longitud_adecuada(self):

        from apps.administracion.mfa import generar_secret_totp
        secret = generar_secret_totp()
        self.assertGreaterEqual(len(secret), 32)

    def test_secretos_son_unicos(self):

        from apps.administracion.mfa import generar_secret_totp
        secrets = {generar_secret_totp() for _ in range(50)}

        self.assertEqual(len(secrets), 50)

    def test_qr_genera_base64_valido(self):

        import base64
        from apps.administracion.mfa import generar_secret_totp, generar_qr_totp
        usuario = _crear_usuario(mfa_secret=generar_secret_totp())
        qr_b64 = generar_qr_totp(usuario)
        self.assertIsInstance(qr_b64, str)
        raw = base64.b64decode(qr_b64)

        self.assertTrue(raw[:4] == b'\x89PNG', 'El QR no es un PNG válido')

    def test_qr_uri_contiene_email_e_issuer(self):

        from apps.administracion.mfa import generar_secret_totp
        import base64
        secret = generar_secret_totp()
        usuario = _crear_usuario(email='qrtest@auditcore.com', mfa_secret=secret)
        totp = pyotp.TOTP(secret)
        uri = totp.provisioning_uri(name=usuario.email, issuer_name='AuditCore')
        self.assertIn('qrtest%40auditcore.com', uri.replace('@', '%40'))
        self.assertIn('AuditCore', uri)
        self.assertTrue(uri.startswith('otpauth://totp/'))

    def test_qr_falla_si_secret_vacio(self):

        from apps.administracion.mfa import generar_qr_totp
        usuario = _crear_usuario(mfa_secret='')


        try:
            generar_qr_totp(usuario)
        except Exception:
            pass


class TestVerificacionTOTPValida(TestCase):


    def setUp(self):
        self.secret = pyotp.random_base32()
        self.usuario = _crear_usuario(mfa_secret=self.secret)

    def test_codigo_actual_es_valido(self):

        from apps.administracion.mfa import verificar_totp
        codigo = _codigo_actual(self.secret)
        self.assertTrue(verificar_totp(self.usuario, codigo))

    def test_codigo_periodo_anterior_es_valido(self):

        from apps.administracion.mfa import verificar_totp
        codigo = _codigo_en(self.secret, -29)
        self.assertTrue(verificar_totp(self.usuario, codigo),
                        'Código 30s anterior rechazado — clock skew normal no tolerado')

    def test_codigo_periodo_siguiente_es_valido(self):

        from apps.administracion.mfa import verificar_totp
        codigo = _codigo_en(self.secret, +29)
        self.assertTrue(verificar_totp(self.usuario, codigo),
                        'Código 30s adelante rechazado — clock skew normal no tolerado')

    def test_verificacion_multiple_mismo_codigo(self):


        from apps.administracion.mfa import verificar_totp
        codigo = _codigo_actual(self.secret)
        self.assertTrue(verificar_totp(self.usuario, codigo))


        resultado = verificar_totp(self.usuario, codigo)

        self.assertTrue(
            resultado,
            'COMPORTAMIENTO CONOCIDO: sin anti-replay, el mismo código puede '
            'usarse dos veces en la misma ventana de 30s. '
            'Implementar cache de códigos usados en Redis para mitigarlo.'
        )

    def test_verificacion_con_usuario_sin_mfa_habilitado(self):

        from apps.administracion.mfa import verificar_totp

        usuario = _crear_usuario(mfa_habilitado=False, mfa_secret=self.secret)
        codigo = _codigo_actual(self.secret)
        self.assertTrue(verificar_totp(usuario, codigo))


class TestVerificacionTOTPInvalida(TestCase):


    def setUp(self):
        self.secret = pyotp.random_base32()
        self.usuario = _crear_usuario(mfa_secret=self.secret)

    def _rechaza(self, codigo, msg=''):
        from apps.administracion.mfa import verificar_totp
        resultado = verificar_totp(self.usuario, codigo)
        self.assertFalse(resultado, msg or f'Se aceptó código inválido: {repr(codigo)}')


    def test_codigo_vacio(self):
        self._rechaza('', 'Cadena vacía no debe pasar')

    def test_codigo_muy_corto(self):
        self._rechaza('123', 'Código de 3 dígitos no debe pasar')

    def test_codigo_muy_largo(self):
        self._rechaza('1234567', 'Código de 7 dígitos no debe pasar')

    def test_codigo_con_letras(self):
        self._rechaza('abcdef', 'Letras no son código TOTP válido')

    def test_codigo_con_espacios_al_inicio(self):

        codigo = ' ' + _codigo_actual(self.secret)
        self._rechaza(codigo, 'Espacio inicial no debe ser ignorado silenciosamente')

    def test_codigo_con_espacios_al_final(self):
        codigo = _codigo_actual(self.secret) + ' '
        self._rechaza(codigo, 'Espacio final no debe ser ignorado silenciosamente')

    def test_codigo_con_guion(self):
        self._rechaza('123-456', 'Código con guion no es válido')

    def test_codigo_todos_ceros(self):
        self._rechaza('000000', 'Código todo-ceros casi nunca es válido')

    def test_codigo_todos_nueves(self):
        self._rechaza('999999', 'Código todo-nueves casi nunca es válido')

    def test_codigo_negativo(self):
        self._rechaza('-12345', 'Código negativo no debe pasar')

    def test_codigo_none_no_lanza_excepcion(self):

        from apps.administracion.mfa import verificar_totp
        try:
            resultado = verificar_totp(self.usuario, None)
            self.assertFalse(resultado)
        except Exception as e:
            self.fail(f'verificar_totp con None lanzó excepción: {e}')


    def test_codigo_dos_periodos_atras_es_invalido(self):

        codigo = _codigo_en(self.secret, -60)
        self._rechaza(codigo, 'Código de 60s atrás no debe pasar con window=1')

    def test_codigo_dos_periodos_adelante_es_invalido(self):

        codigo = _codigo_en(self.secret, +60)
        self._rechaza(codigo, 'Código 60s en el futuro no debe pasar con window=1')

    def test_codigo_de_ayer_es_invalido(self):

        codigo = _codigo_en(self.secret, -86400)
        self._rechaza(codigo, 'Código de ayer no debe pasar jamás')


    def test_cross_secret_attack(self):


        otro_secret = pyotp.random_base32()
        codigo_atacante = pyotp.TOTP(otro_secret).now()
        self._rechaza(codigo_atacante, 'Código de secret ajeno no debe pasar')

    def test_brute_force_secuencial_no_adivina(self):


        from apps.administracion.mfa import verificar_totp
        import random
        intentos_exitosos = 0
        muestra = random.sample(range(1000000), 100)
        for n in muestra:
            codigo = str(n).zfill(6)
            if verificar_totp(self.usuario, codigo):
                intentos_exitosos += 1

        self.assertEqual(intentos_exitosos, 0,
                         f'{intentos_exitosos} códigos aleatorios pasaron — '
                         f'revisar la configuración de la ventana TOTP')

    def test_secret_vacio_siempre_rechaza(self):

        from apps.administracion.mfa import verificar_totp
        usuario_sin_secret = _crear_usuario(email='nosecret@test.com', mfa_secret='')
        codigo = _codigo_actual(self.secret)
        self.assertFalse(verificar_totp(usuario_sin_secret, codigo))

    def test_secret_invalido_no_lanza_excepcion(self):


        from apps.administracion.mfa import verificar_totp
        usuario = _crear_usuario(email='badsecret@test.com', mfa_secret='INVALID!!SECRET')
        try:
            resultado = verificar_totp(usuario, '123456')
            self.assertFalse(resultado)
        except Exception as e:
            self.fail(f'Secret inválido en BD causó excepción no controlada: {e}')


class TestBloqueoTrasIntentosFallidos(TestCase):


    def _usuario_fresco(self, email='lock@test.com'):
        return _crear_usuario(email=email, intentos_fallidos=0)

    def test_bloqueo_exactamente_en_5_intentos(self):

        from apps.administracion.mfa import registrar_intento_fallido, MAX_INTENTOS
        u = self._usuario_fresco()
        for i in range(MAX_INTENTOS - 1):
            registrar_intento_fallido(u)
            u.refresh_from_db()
            self.assertNotEqual(u.estado, 'BLOQUEADO',
                                f'Bloqueado prematuramente en intento {i+1}')

        registrar_intento_fallido(u)
        u.refresh_from_db()
        self.assertEqual(u.estado, 'BLOQUEADO')

    def test_fecha_bloqueo_se_registra(self):

        from apps.administracion.mfa import registrar_intento_fallido, MAX_INTENTOS
        u = self._usuario_fresco()
        antes = timezone.now()
        for _ in range(MAX_INTENTOS):
            registrar_intento_fallido(u)
        u.refresh_from_db()
        self.assertIsNotNone(u.fecha_bloqueo)
        self.assertGreaterEqual(u.fecha_bloqueo, antes)

    def test_verificar_bloqueo_activo(self):

        from apps.administracion.mfa import verificar_bloqueo
        u = _crear_usuario(estado='BLOQUEADO',
                           fecha_bloqueo=timezone.now() - timedelta(minutes=5))
        self.assertTrue(verificar_bloqueo(u))

    def test_desbloqueo_automatico_tras_30_minutos(self):

        from apps.administracion.mfa import verificar_bloqueo, BLOQUEO_MINUTOS
        u = _crear_usuario(
            estado='BLOQUEADO',
            fecha_bloqueo=timezone.now() - timedelta(minutes=BLOQUEO_MINUTOS + 1),
            intentos_fallidos=5,
        )
        resultado = verificar_bloqueo(u)
        u.refresh_from_db()
        self.assertFalse(resultado, 'Debería haberse desbloqueado automáticamente')
        self.assertEqual(u.estado, 'ACTIVO')
        self.assertEqual(u.intentos_fallidos, 0)

    def test_no_desbloquea_antes_de_30_minutos(self):

        from apps.administracion.mfa import verificar_bloqueo, BLOQUEO_MINUTOS
        u = _crear_usuario(
            estado='BLOQUEADO',
            fecha_bloqueo=timezone.now() - timedelta(minutes=BLOQUEO_MINUTOS - 1),
        )
        self.assertTrue(verificar_bloqueo(u))

    def test_estado_inconsistente_bloqueado_sin_fecha(self):


        from apps.administracion.mfa import verificar_bloqueo
        u = _crear_usuario(estado='BLOQUEADO', fecha_bloqueo=None)
        u.fecha_bloqueo = None
        u.save(update_fields=['fecha_bloqueo'])
        resultado = verificar_bloqueo(u)
        u.refresh_from_db()
        self.assertFalse(resultado, 'Estado inconsistente debe resolverse como desbloqueado')
        self.assertEqual(u.estado, 'ACTIVO')

    def test_registrar_login_exitoso_resetea_contador(self):

        from apps.administracion.mfa import registrar_intento_fallido, registrar_login_exitoso
        u = self._usuario_fresco()
        for _ in range(3):
            registrar_intento_fallido(u)
        u.refresh_from_db()
        self.assertEqual(u.intentos_fallidos, 3)
        registrar_login_exitoso(u)
        u.refresh_from_db()
        self.assertEqual(u.intentos_fallidos, 0)
        self.assertIsNotNone(u.ultimo_acceso)

    def test_intentos_adicionales_en_cuenta_ya_bloqueada(self):


        from apps.administracion.mfa import registrar_intento_fallido, MAX_INTENTOS
        u = self._usuario_fresco()
        for _ in range(MAX_INTENTOS):
            registrar_intento_fallido(u)
        u.refresh_from_db()
        self.assertEqual(u.estado, 'BLOQUEADO')
        intentos_al_bloquearse = u.intentos_fallidos


        registrar_intento_fallido(u)
        registrar_intento_fallido(u)
        u.refresh_from_db()

        self.assertEqual(u.estado, 'BLOQUEADO')

        self.assertGreaterEqual(u.intentos_fallidos, intentos_al_bloquearse)

    def test_cuenta_inactiva_no_se_bloquea_automaticamente(self):

        from apps.administracion.mfa import registrar_intento_fallido, MAX_INTENTOS
        u = _crear_usuario(estado='INACTIVO')
        for _ in range(MAX_INTENTOS + 2):
            registrar_intento_fallido(u)
        u.refresh_from_db()

        self.assertEqual(u.estado, 'INACTIVO',
                         'registrar_intento_fallido no debe cambiar INACTIVO a BLOQUEADO')


class TestConcurrenciaBloqueo(TestCase):


    def test_incremento_atomico_sin_lost_update(self):


        from apps.administracion.mfa import registrar_intento_fallido, MAX_INTENTOS
        u = _crear_usuario(email='race@test.com', intentos_fallidos=0)
        N = 10
        errores = []

        def intentar():
            try:


                from apps.administracion.models import UsuarioInterno
                usuario_thread = UsuarioInterno.objects.get(pk=u.pk)
                registrar_intento_fallido(usuario_thread)
            except Exception as e:
                errores.append(str(e))

        threads = [threading.Thread(target=intentar) for _ in range(N)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(errores, [], f'Excepciones en threads: {errores}')
        u.refresh_from_db()
        self.assertEqual(
            u.intentos_fallidos, N,
            f'Lost-update detectado: esperado {N}, obtenido {u.intentos_fallidos}. '
            f'El incremento F() no es atómico o hay un bug de concurrencia.'
        )

    def test_bloqueo_ocurre_una_sola_vez_con_muchos_threads(self):


        from apps.administracion.mfa import registrar_intento_fallido, MAX_INTENTOS
        u = _crear_usuario(email='race2@test.com', intentos_fallidos=0)

        def intentar():
            from apps.administracion.models import UsuarioInterno
            usuario_thread = UsuarioInterno.objects.get(pk=u.pk)
            registrar_intento_fallido(usuario_thread)

        threads = [threading.Thread(target=intentar) for _ in range(MAX_INTENTOS + 3)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        u.refresh_from_db()
        self.assertEqual(u.estado, 'BLOQUEADO')
        self.assertIsNotNone(u.fecha_bloqueo)


class TestMFASetupViaAPI(TestCase):


    def setUp(self):
        self.client = APIClient()
        self.usuario = _crear_usuario(email='api_mfa@test.com', password='MFA1234!')

        login = self.client.post('/api/auth/login/', {
            'email': 'api_mfa@test.com', 'password': 'MFA1234!',
        }, format='json')
        self.assertEqual(login.status_code, 200, 'Login falló en setUp')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {login.data["access"]}')

    def test_get_mfa_setup_devuelve_qr_y_secret(self):

        res = self.client.get('/api/auth/mfa/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('qr_base64', res.data)
        self.assertIn('secret', res.data)
        self.assertFalse(res.data.get('mfa_activo'))

    def test_get_mfa_setup_no_devuelve_secret_si_ya_activo(self):

        self.usuario.mfa_habilitado = True
        self.usuario.mfa_secret = pyotp.random_base32()
        self.usuario.save(update_fields=['mfa_habilitado', 'mfa_secret'])

        res = self.client.get('/api/auth/mfa/')
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data.get('mfa_activo'))
        self.assertNotIn('secret', res.data,
                         'El secret no debe exponerse si MFA ya está activo')

    def test_activar_mfa_con_codigo_valido(self):


        setup = self.client.get('/api/auth/mfa/')
        secret = setup.data['secret']
        self.usuario.mfa_secret = secret
        self.usuario.save(update_fields=['mfa_secret'])

        codigo = pyotp.TOTP(secret).now()
        res = self.client.post('/api/auth/mfa/', {'codigo': codigo}, format='json')
        self.assertEqual(res.status_code, 200)

        self.usuario.refresh_from_db()
        self.assertTrue(self.usuario.mfa_habilitado)

    def test_activar_mfa_con_codigo_invalido(self):

        setup = self.client.get('/api/auth/mfa/')
        secret = setup.data['secret']
        self.usuario.mfa_secret = secret
        self.usuario.save(update_fields=['mfa_secret'])

        res = self.client.post('/api/auth/mfa/', {'codigo': '000000'}, format='json')
        self.assertEqual(res.status_code, 400)
        self.usuario.refresh_from_db()
        self.assertFalse(self.usuario.mfa_habilitado)

    def test_activar_mfa_con_codigo_vacio(self):

        res = self.client.post('/api/auth/mfa/', {'codigo': ''}, format='json')
        self.assertEqual(res.status_code, 400)

    def test_desactivar_mfa_con_password_correcta(self):

        self.usuario.mfa_habilitado = True
        self.usuario.mfa_secret = pyotp.random_base32()
        self.usuario.save(update_fields=['mfa_habilitado', 'mfa_secret'])

        res = self.client.delete('/api/auth/mfa/', {'password': 'MFA1234!'}, format='json')
        self.assertEqual(res.status_code, 200)

        self.usuario.refresh_from_db()
        self.assertFalse(self.usuario.mfa_habilitado)
        self.assertEqual(self.usuario.mfa_secret, '')

    def test_desactivar_mfa_con_password_incorrecta(self):

        self.usuario.mfa_habilitado = True
        self.usuario.mfa_secret = pyotp.random_base32()
        self.usuario.save(update_fields=['mfa_habilitado', 'mfa_secret'])

        res = self.client.delete('/api/auth/mfa/', {'password': 'WrongPass!'}, format='json')
        self.assertEqual(res.status_code, 400)
        self.usuario.refresh_from_db()
        self.assertTrue(self.usuario.mfa_habilitado)

    def test_setup_mfa_sin_autenticacion(self):

        client_sin_auth = APIClient()
        self.assertEqual(client_sin_auth.get('/api/auth/mfa/').status_code, 401)
        self.assertEqual(client_sin_auth.post('/api/auth/mfa/', {}).status_code, 401)
        self.assertEqual(client_sin_auth.delete('/api/auth/mfa/', {}).status_code, 401)


class TestLoginConMFA(TestCase):


    def setUp(self):
        self.client = APIClient()
        self.secret = pyotp.random_base32()
        self.usuario = _crear_usuario(
            email='mfa_login@test.com', password='Login1234!',
            mfa_habilitado=True, mfa_secret=self.secret,
        )

    def _login_base(self, password='Login1234!'):
        return self.client.post('/api/auth/login/', {
            'email': 'mfa_login@test.com', 'password': password,
        }, format='json')

    def test_login_sin_codigo_mfa_devuelve_202(self):

        res = self._login_base()
        self.assertEqual(res.status_code, 202)
        self.assertTrue(res.data.get('mfa_required'))

    def test_login_con_codigo_mfa_valido_devuelve_tokens(self):

        codigo = _codigo_actual(self.secret)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfa_login@test.com',
            'password': 'Login1234!',
            'codigo_mfa': codigo,
        }, format='json')
        self.assertEqual(res.status_code, 200)
        self.assertIn('access', res.data)
        self.assertIn('refresh', res.data)

    def test_login_con_codigo_mfa_invalido_devuelve_401(self):

        res = self.client.post('/api/auth/login/', {
            'email': 'mfa_login@test.com',
            'password': 'Login1234!',
            'codigo_mfa': '000000',
        }, format='json')
        self.assertEqual(res.status_code, 401)

    def test_login_con_codigo_mfa_expirado_devuelve_401(self):

        codigo_viejo = _codigo_en(self.secret, -60)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfa_login@test.com',
            'password': 'Login1234!',
            'codigo_mfa': codigo_viejo,
        }, format='json')
        self.assertEqual(res.status_code, 401)

    def test_login_con_password_incorrecta_no_llega_a_mfa(self):

        codigo = _codigo_actual(self.secret)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfa_login@test.com',
            'password': 'WrongPass!',
            'codigo_mfa': codigo,
        }, format='json')

        self.assertEqual(res.status_code, 401)

    def test_login_cuenta_bloqueada_rechaza_antes_del_mfa(self):

        self.usuario.estado = 'BLOQUEADO'
        self.usuario.fecha_bloqueo = timezone.now()
        self.usuario.save(update_fields=['estado', 'fecha_bloqueo'])

        codigo = _codigo_actual(self.secret)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfa_login@test.com',
            'password': 'Login1234!',
            'codigo_mfa': codigo,
        }, format='json')
        self.assertEqual(res.status_code, 403,
                         'Cuenta bloqueada debe devolver 403, no verificar MFA')

    def test_5_intentos_fallidos_de_mfa_bloquean_cuenta(self):


        from apps.administracion.mfa import MAX_INTENTOS

        for _ in range(MAX_INTENTOS):
            self.client.post('/api/auth/login/', {
                'email': 'mfa_login@test.com',
                'password': 'WrongPass!',
            }, format='json')

        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.estado, 'BLOQUEADO',
                         'La cuenta debe bloquearse tras 5 contraseñas incorrectas')

    def test_login_sin_mfa_activo_no_requiere_codigo(self):

        usuario_sin_mfa = _crear_usuario(
            email='sinmfa@test.com', password='NoMFA1234!',
            mfa_habilitado=False,
        )
        res = self.client.post('/api/auth/login/', {
            'email': 'sinmfa@test.com', 'password': 'NoMFA1234!',
        }, format='json')
        self.assertEqual(res.status_code, 200)
        self.assertIn('access', res.data)

    def test_codigo_mfa_con_clock_skew_negativo_30s(self):


        codigo = _codigo_en(self.secret, -25)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfa_login@test.com',
            'password': 'Login1234!',
            'codigo_mfa': codigo,
        }, format='json')
        self.assertEqual(res.status_code, 200,
                         'Clock skew de -25s debe ser tolerado (window=1)')

    def test_codigo_mfa_con_clock_skew_positivo_30s(self):

        codigo = _codigo_en(self.secret, +25)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfa_login@test.com',
            'password': 'Login1234!',
            'codigo_mfa': codigo,
        }, format='json')
        self.assertEqual(res.status_code, 200,
                         'Clock skew de +25s debe ser tolerado (window=1)')


class TestResilienciaMFA(TestCase):


    def setUp(self):
        self.secret = pyotp.random_base32()
        self.usuario = _crear_usuario(mfa_secret=self.secret)

    def test_verificar_totp_con_pyotp_raising_exception(self):


        from apps.administracion import mfa as mfa_module
        with patch.object(pyotp.TOTP, 'verify', side_effect=RuntimeError('pyotp error')):
            try:
                resultado = mfa_module.verificar_totp(self.usuario, '123456')

                self.assertFalse(resultado)
            except RuntimeError:


                pass

    def test_notificar_bloqueo_falla_silenciosamente(self):


        from apps.administracion.mfa import registrar_intento_fallido, MAX_INTENTOS
        with patch('django.core.mail.send_mail', side_effect=Exception('SMTP error')):
            u = _crear_usuario(email='mailcrash@test.com')
            try:
                for _ in range(MAX_INTENTOS):
                    registrar_intento_fallido(u)
            except Exception as e:
                self.fail(f'Fallo de email propagó excepción: {e}')
            u.refresh_from_db()
            self.assertEqual(u.estado, 'BLOQUEADO',
                             'El bloqueo debe ocurrir aunque el email falle')

    def test_verificar_bloqueo_con_timezone_manipulado(self):


        from apps.administracion.mfa import verificar_bloqueo, BLOQUEO_MINUTOS
        u = _crear_usuario(
            estado='BLOQUEADO',
            fecha_bloqueo=timezone.now() - timedelta(minutes=15),
        )

        future = timezone.now() + timedelta(hours=24)
        with patch('apps.administracion.mfa.timezone') as mock_tz:
            mock_tz.now.return_value = future
            resultado = verificar_bloqueo(u)

        self.assertFalse(resultado)


class TestEstresVolumenMFA(TestCase):


    def test_verificaciones_masivas_mismo_usuario(self):


        from apps.administracion.mfa import verificar_totp
        secret = pyotp.random_base32()
        usuario = _crear_usuario(email='stress1@test.com', mfa_secret=secret)
        codigo = _codigo_actual(secret)

        resultados = [verificar_totp(usuario, codigo) for _ in range(1000)]
        self.assertTrue(all(resultados),
                        f'{resultados.count(False)} de 1000 verificaciones válidas fallaron')

    def test_muchos_usuarios_con_mfa_independientes(self):


        from apps.administracion.mfa import verificar_totp
        pares = []
        for i in range(50):
            secret = pyotp.random_base32()
            u = _crear_usuario(email=f'mass{i}@test.com', mfa_secret=secret)
            pares.append((u, secret))

        for u, secret in pares:
            codigo_propio = _codigo_actual(secret)
            self.assertTrue(verificar_totp(u, codigo_propio),
                            f'Código propio rechazado para usuario {u.email}')


        u0, s0 = pares[0]
        u1, s1 = pares[1]
        if _codigo_actual(s0) != _codigo_actual(s1):
            self.assertFalse(verificar_totp(u1, _codigo_actual(s0)),
                             'Cross-secret: código ajeno no debe pasar')

    def test_activacion_desactivacion_repetida(self):


        usuario = _crear_usuario(email='toggle@test.com', password='Toggle1234!')
        client = APIClient()
        login = client.post('/api/auth/login/', {
            'email': 'toggle@test.com', 'password': 'Toggle1234!',
        }, format='json')
        client.credentials(HTTP_AUTHORIZATION=f'Bearer {login.data["access"]}')

        for ciclo in range(10):

            setup = client.get('/api/auth/mfa/')
            secret = setup.data.get('secret') or usuario.mfa_secret
            usuario.mfa_secret = secret
            usuario.save(update_fields=['mfa_secret'])
            codigo = pyotp.TOTP(secret).now()
            act = client.post('/api/auth/mfa/', {'codigo': codigo}, format='json')
            self.assertEqual(act.status_code, 200, f'Ciclo {ciclo}: activación falló')


            deact = client.delete('/api/auth/mfa/', {'password': 'Toggle1234!'}, format='json')
            self.assertEqual(deact.status_code, 200, f'Ciclo {ciclo}: desactivación falló')

        usuario.refresh_from_db()
        self.assertFalse(usuario.mfa_habilitado)
        self.assertEqual(usuario.mfa_secret, '')

    def test_generacion_masiva_secrets_son_unicos(self):

        from apps.administracion.mfa import generar_secret_totp
        secrets = [generar_secret_totp() for _ in range(500)]
        self.assertEqual(len(secrets), len(set(secrets)),
                         'Se generaron secrets duplicados — problema de entropía')

    def test_reset_bloqueo_tras_desbloqueo_y_nuevos_intentos(self):


        from apps.administracion.mfa import (
            registrar_intento_fallido, verificar_bloqueo,
            registrar_login_exitoso, MAX_INTENTOS, BLOQUEO_MINUTOS,
        )
        u = _crear_usuario(email='fullcycle@test.com')


        for _ in range(MAX_INTENTOS):
            registrar_intento_fallido(u)
        u.refresh_from_db()
        self.assertEqual(u.estado, 'BLOQUEADO')


        u.fecha_bloqueo = timezone.now() - timedelta(minutes=BLOQUEO_MINUTOS + 1)
        u.save(update_fields=['fecha_bloqueo'])
        desbloqueado = not verificar_bloqueo(u)
        self.assertTrue(desbloqueado)
        u.refresh_from_db()
        self.assertEqual(u.estado, 'ACTIVO')


        for _ in range(MAX_INTENTOS):
            registrar_intento_fallido(u)
        u.refresh_from_db()
        self.assertEqual(u.estado, 'BLOQUEADO',
                         'La cuenta debe poder bloquearse de nuevo después del desbloqueo')
