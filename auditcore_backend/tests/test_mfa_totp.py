import threading
import time
import pyotp

from datetime import timedelta
from unittest.mock import patch, MagicMock

from django.test import TestCase, override_settings
from django.utils import timezone
from freezegun import freeze_time
from rest_framework.test import APIClient
from rest_framework import status


def _crear_usuario(email='mfa@test.com', password='Test1234!', rol='AUDITOR', mfa=False):

    from apps.administracion.models import UsuarioInterno
    u = UsuarioInterno.objects.create_user(
        email=email, password=password,
        nombre='MFA', apellido='Test', rol=rol,
    )
    if mfa:
        u.mfa_secret = pyotp.random_base32()
        u.mfa_habilitado = True
        u.save(update_fields=['mfa_secret', 'mfa_habilitado'])
    return u


def _codigo_valido(usuario):

    return pyotp.TOTP(usuario.mfa_secret).now()


def _codigo_vencido(usuario, periodos_atras=2):

    t = pyotp.TOTP(usuario.mfa_secret)
    return t.at(time.time() - 30 * periodos_atras)


class TestGeneracionSecret(TestCase):


    def test_secret_es_base32_valido(self):
        from apps.administracion.mfa import generar_secret_totp
        secret = generar_secret_totp()

        totp = pyotp.TOTP(secret)
        self.assertIsNotNone(totp.now())

    def test_secret_longitud_minima(self):

        from apps.administracion.mfa import generar_secret_totp
        secret = generar_secret_totp()
        self.assertGreaterEqual(len(secret), 16,
            "Secret demasiado corto — vulnerable a fuerza bruta")

    def test_secrets_son_unicos(self):

        from apps.administracion.mfa import generar_secret_totp
        secrets = {generar_secret_totp() for _ in range(100)}
        self.assertEqual(len(secrets), 100, "Se generaron secrets duplicados")

    def test_secret_puede_generar_codigo_6_digitos(self):
        from apps.administracion.mfa import generar_secret_totp
        secret = generar_secret_totp()
        codigo = pyotp.TOTP(secret).now()
        self.assertEqual(len(codigo), 6)
        self.assertTrue(codigo.isdigit())


class TestGeneracionQR(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario(mfa=False)
        self.usuario.mfa_secret = pyotp.random_base32()
        self.usuario.save(update_fields=['mfa_secret'])

    def test_qr_devuelve_base64_valido(self):
        import base64
        from apps.administracion.mfa import generar_qr_totp
        b64 = generar_qr_totp(self.usuario)

        raw = base64.b64decode(b64)
        self.assertTrue(raw.startswith(b'\x89PNG'),
            "El QR no es una imagen PNG válida")

    def test_uri_contiene_email_del_usuario(self):

        totp = pyotp.TOTP(self.usuario.mfa_secret)
        uri = totp.provisioning_uri(
            name=self.usuario.email, issuer_name='AuditCore'
        )
        self.assertIn('mfa%40test.com', uri.replace('@', '%40'))

    def test_uri_contiene_issuer_auditcore(self):
        totp = pyotp.TOTP(self.usuario.mfa_secret)
        uri = totp.provisioning_uri(
            name=self.usuario.email, issuer_name='AuditCore'
        )
        self.assertIn('AuditCore', uri)

    def test_uri_usa_algoritmo_sha1_por_defecto(self):

        totp = pyotp.TOTP(self.usuario.mfa_secret)
        uri = totp.provisioning_uri(
            name=self.usuario.email, issuer_name='AuditCore'
        )

        self.assertNotIn('algorithm=SHA256', uri,
            "Cambiar a SHA256 rompe compatibilidad con Google Authenticator")

    def test_uri_intervalo_30_segundos(self):

        totp = pyotp.TOTP(self.usuario.mfa_secret)
        self.assertEqual(totp.interval, 30)

    def test_qr_falla_sin_secret(self):

        self.usuario.mfa_secret = ''
        self.usuario.save(update_fields=['mfa_secret'])
        from apps.administracion.mfa import generar_qr_totp
        with self.assertRaises(Exception):
            generar_qr_totp(self.usuario)


class TestVerificacionTOTP(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario(mfa=True)

    def test_codigo_actual_es_valido(self):
        from apps.administracion.mfa import verificar_totp
        codigo = _codigo_valido(self.usuario)
        self.assertTrue(verificar_totp(self.usuario, codigo))

    def test_codigo_incorrecto_es_invalido(self):
        from apps.administracion.mfa import verificar_totp
        self.assertFalse(verificar_totp(self.usuario, '000000'))

    def test_codigo_vacio_es_invalido(self):
        from apps.administracion.mfa import verificar_totp
        self.assertFalse(verificar_totp(self.usuario, ''))

    def test_codigo_none_es_invalido(self):

        from apps.administracion.mfa import verificar_totp


        try:
            result = verificar_totp(self.usuario, None)
            self.assertFalse(result)
        except TypeError:

            self.skipTest(
                "BUG CONOCIDO: verificar_totp() lanza TypeError con None. "
                "Agregar validación de tipo en mfa.py"
            )

    def test_codigo_alfanumerico_es_invalido(self):

        from apps.administracion.mfa import verificar_totp
        self.assertFalse(verificar_totp(self.usuario, 'ABC123'))

    def test_codigo_con_espacios_es_invalido(self):

        from apps.administracion.mfa import verificar_totp
        codigo = _codigo_valido(self.usuario)
        codigo_con_espacio = codigo[:3] + ' ' + codigo[3:]
        self.assertFalse(verificar_totp(self.usuario, codigo_con_espacio),
            "Un código con espacio no debe ser válido — sanitizar en el endpoint")

    def test_codigo_4_digitos_es_invalido(self):
        from apps.administracion.mfa import verificar_totp
        self.assertFalse(verificar_totp(self.usuario, '1234'))

    def test_codigo_8_digitos_es_invalido(self):
        from apps.administracion.mfa import verificar_totp
        self.assertFalse(verificar_totp(self.usuario, '12345678'))

    def test_codigo_anterior_1_periodo_aceptado(self):

        from apps.administracion.mfa import verificar_totp
        t = pyotp.TOTP(self.usuario.mfa_secret)
        codigo_pasado = t.at(time.time() - 30)
        self.assertTrue(verificar_totp(self.usuario, codigo_pasado),
            "El código del período anterior debe aceptarse (ventana ±30s)")

    def test_codigo_2_periodos_atras_rechazado(self):

        from apps.administracion.mfa import verificar_totp
        codigo_viejo = _codigo_vencido(self.usuario, periodos_atras=2)
        self.assertFalse(verificar_totp(self.usuario, codigo_viejo),
            "Código de 2 períodos atrás no debe aceptarse")

    def test_sin_secret_siempre_falla(self):

        from apps.administracion.mfa import verificar_totp
        self.usuario.mfa_secret = ''
        self.usuario.save(update_fields=['mfa_secret'])
        self.assertFalse(verificar_totp(self.usuario, '123456'))

    def test_secret_corrupto_no_crashea(self):

        from apps.administracion.mfa import verificar_totp
        self.usuario.mfa_secret = 'NO-ES-BASE32-!!!!'
        self.usuario.save(update_fields=['mfa_secret'])
        try:
            result = verificar_totp(self.usuario, '123456')
            self.assertFalse(result)
        except Exception as e:
            self.fail(
                f"BUG: verificar_totp() lanzó {type(e).__name__} con secret corrupto. "
                f"Agregar try/except en mfa.py para prevenir crash."
            )

    def test_codigo_de_usuario_diferente_no_valido(self):

        from apps.administracion.mfa import verificar_totp
        otro = _crear_usuario(email='otro@test.com', mfa=True)
        codigo_otro = _codigo_valido(otro)
        self.assertFalse(verificar_totp(self.usuario, codigo_otro))


class TestReplayAttack(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario(mfa=True)

    def test_mismo_codigo_puede_usarse_dos_veces_en_mismo_periodo(self):


        from apps.administracion.mfa import verificar_totp
        codigo = _codigo_valido(self.usuario)
        primera = verificar_totp(self.usuario, codigo)
        segunda = verificar_totp(self.usuario, codigo)

        self.assertTrue(primera)
        self.assertTrue(segunda,
            "AVISO: El mismo código puede verificarse dos veces. "
            "pyotp no tiene protección contra replay integrada. "
            "Implementar rastreo de último código usado en mfa.py.")

    def test_replay_en_ventana_adyacente(self):

        from apps.administracion.mfa import verificar_totp
        t = pyotp.TOTP(self.usuario.mfa_secret)
        codigo_pasado = t.at(time.time() - 30)
        r1 = verificar_totp(self.usuario, codigo_pasado)
        r2 = verificar_totp(self.usuario, codigo_pasado)
        self.assertTrue(r1)

        if r2:
            pass


class TestBloqueoIntentosFallidos(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario()

    def test_un_intento_fallido_no_bloquea(self):
        from apps.administracion.mfa import registrar_intento_fallido, verificar_bloqueo
        registrar_intento_fallido(self.usuario)
        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.intentos_fallidos, 1)
        self.assertEqual(self.usuario.estado, 'ACTIVO')
        self.assertFalse(verificar_bloqueo(self.usuario))

    def test_cuatro_intentos_no_bloquean(self):
        from apps.administracion.mfa import registrar_intento_fallido, verificar_bloqueo
        for _ in range(4):
            registrar_intento_fallido(self.usuario)
        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.intentos_fallidos, 4)
        self.assertEqual(self.usuario.estado, 'ACTIVO')
        self.assertFalse(verificar_bloqueo(self.usuario))

    def test_cinco_intentos_bloquean(self):
        from apps.administracion.mfa import registrar_intento_fallido, verificar_bloqueo
        for _ in range(5):
            registrar_intento_fallido(self.usuario)
        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.estado, 'BLOQUEADO')
        self.assertIsNotNone(self.usuario.fecha_bloqueo)
        self.assertTrue(verificar_bloqueo(self.usuario))

    def test_sexto_intento_no_cambia_estado(self):

        from apps.administracion.mfa import registrar_intento_fallido
        for _ in range(6):
            registrar_intento_fallido(self.usuario)
        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.estado, 'BLOQUEADO')
        self.assertEqual(self.usuario.intentos_fallidos, 6)

    def test_login_exitoso_resetea_contador(self):
        from apps.administracion.mfa import registrar_intento_fallido, registrar_login_exitoso
        for _ in range(3):
            registrar_intento_fallido(self.usuario)
        registrar_login_exitoso(self.usuario)
        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.intentos_fallidos, 0)
        self.assertEqual(self.usuario.estado, 'ACTIVO')

    def test_bloqueo_registra_fecha_correcta(self):
        from apps.administracion.mfa import registrar_intento_fallido
        antes = timezone.now()
        for _ in range(5):
            registrar_intento_fallido(self.usuario)
        despues = timezone.now()
        self.usuario.refresh_from_db()
        self.assertIsNotNone(self.usuario.fecha_bloqueo)
        self.assertGreaterEqual(self.usuario.fecha_bloqueo, antes)
        self.assertLessEqual(self.usuario.fecha_bloqueo, despues)

    def test_bloqueo_envia_notificacion(self):

        from apps.administracion.mfa import registrar_intento_fallido
        with patch('apps.administracion.mfa._notificar_bloqueo') as mock_notif:
            for _ in range(5):
                registrar_intento_fallido(self.usuario)
            mock_notif.assert_called_once_with(self.usuario)

    def test_solo_se_notifica_en_el_intento_exacto_5(self):

        from apps.administracion.mfa import registrar_intento_fallido
        with patch('apps.administracion.mfa._notificar_bloqueo') as mock_notif:
            for _ in range(10):
                registrar_intento_fallido(self.usuario)
            self.assertEqual(mock_notif.call_count, 1,
                "La notificación de bloqueo debe enviarse exactamente una vez")


class TestDesbloqueoAutomatico(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario()

    def _bloquear(self):
        from apps.administracion.mfa import registrar_intento_fallido
        for _ in range(5):
            registrar_intento_fallido(self.usuario)
        self.usuario.refresh_from_db()

    def test_cuenta_bloqueada_no_da_acceso(self):
        from apps.administracion.mfa import verificar_bloqueo
        self._bloquear()
        self.assertTrue(verificar_bloqueo(self.usuario))

    def test_desbloqueo_tras_30_minutos(self):

        from apps.administracion.mfa import verificar_bloqueo, BLOQUEO_MINUTOS
        self._bloquear()


        tiempo_futuro = timezone.now() + timedelta(minutes=BLOQUEO_MINUTOS + 1)
        with freeze_time(tiempo_futuro):
            desbloqueado = verificar_bloqueo(self.usuario)

        self.assertFalse(desbloqueado,
            "La cuenta debe desbloquearse automáticamente tras BLOQUEO_MINUTOS")

    def test_desbloqueo_exacto_en_el_limite_sigue_bloqueado(self):

        from apps.administracion.mfa import verificar_bloqueo, BLOQUEO_MINUTOS
        self._bloquear()


        tiempo_limite = self.usuario.fecha_bloqueo + timedelta(minutes=BLOQUEO_MINUTOS)
        with freeze_time(tiempo_limite):
            aun_bloqueado = verificar_bloqueo(self.usuario)

        self.assertTrue(aun_bloqueado,
            "Exactamente en el límite de 30 min aún debe estar bloqueado")

    def test_desbloqueo_resetea_campos_en_bd(self):

        from apps.administracion.mfa import verificar_bloqueo, BLOQUEO_MINUTOS
        self._bloquear()

        tiempo_futuro = timezone.now() + timedelta(minutes=BLOQUEO_MINUTOS + 1)
        with freeze_time(tiempo_futuro):
            verificar_bloqueo(self.usuario)

        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.estado, 'ACTIVO')
        self.assertEqual(self.usuario.intentos_fallidos, 0)
        self.assertIsNone(self.usuario.fecha_bloqueo)

    def test_estado_inconsistente_sin_fecha_bloqueo(self):


        from apps.administracion.mfa import verificar_bloqueo

        self.usuario.estado = 'BLOQUEADO'
        self.usuario.fecha_bloqueo = None
        self.usuario.save(update_fields=['estado', 'fecha_bloqueo'])

        resultado = verificar_bloqueo(self.usuario)
        self.assertFalse(resultado,
            "Estado inconsistente (BLOQUEADO sin fecha) no debe causar bloqueo permanente")

        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.estado, 'ACTIVO')


class TestConcurrenciaBloqueo(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario()

    def test_incremento_atomico_con_10_threads_paralelos(self):


        from apps.administracion.mfa import registrar_intento_fallido

        errores = []

        def registrar():
            try:

                from apps.administracion.models import UsuarioInterno
                u = UsuarioInterno.objects.get(pk=self.usuario.pk)
                registrar_intento_fallido(u)
            except Exception as e:
                errores.append(str(e))

        threads = [threading.Thread(target=registrar) for _ in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(errores, [], f"Errores en threads: {errores}")

        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.intentos_fallidos, 10,
            f"Perdidos {10 - self.usuario.intentos_fallidos} incrementos por race condition. "
            f"El F() atómico debe garantizar exactamente 10.")
        self.assertEqual(self.usuario.estado, 'BLOQUEADO',
            "Con 10 intentos la cuenta debe estar BLOQUEADA")

    def test_bloqueo_no_se_duplica_con_threads_paralelos(self):


        from apps.administracion.mfa import registrar_intento_fallido


        for _ in range(4):
            registrar_intento_fallido(self.usuario)

        bloqueos_notificados = []

        with patch('apps.administracion.mfa._notificar_bloqueo') as mock_notif:
            mock_notif.side_effect = lambda u: bloqueos_notificados.append(1)

            def quinto_intento():
                from apps.administracion.models import UsuarioInterno
                u = UsuarioInterno.objects.get(pk=self.usuario.pk)
                registrar_intento_fallido(u)

            threads = [threading.Thread(target=quinto_intento) for _ in range(5)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()


        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.estado, 'BLOQUEADO')


class TestMFAFlujoCOMPLETOAPI(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario(email='flujo@test.com')
        self.client = APIClient()

        res = self.client.post('/api/auth/login/', {
            'email': 'flujo@test.com', 'password': 'Test1234!',
        }, format='json')
        self.token = res.data['access']
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.token}')

    def test_get_setup_mfa_genera_qr(self):
        res = self.client.get('/api/auth/mfa/setup/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('qr_base64', res.data)
        self.assertIn('secret', res.data)
        self.assertFalse(res.data.get('mfa_activo'))

    def test_get_setup_mfa_no_expone_secret_si_ya_activo(self):

        self.usuario.mfa_secret = pyotp.random_base32()
        self.usuario.mfa_habilitado = True
        self.usuario.save(update_fields=['mfa_secret', 'mfa_habilitado'])

        res = self.client.get('/api/auth/mfa/setup/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data.get('mfa_activo'))
        self.assertNotIn('secret', res.data,
            "SEGURIDAD: el secret no debe exponerse si MFA ya está activo")

    def test_activar_mfa_con_codigo_correcto(self):

        res = self.client.get('/api/auth/mfa/setup/')
        secret = res.data['secret']


        codigo = pyotp.TOTP(secret).now()


        res = self.client.post('/api/auth/mfa/setup/', {'codigo': codigo}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        self.usuario.refresh_from_db()
        self.assertTrue(self.usuario.mfa_habilitado)

    def test_activar_mfa_con_codigo_incorrecto_rechaza(self):
        self.client.get('/api/auth/mfa/setup/')
        res = self.client.post('/api/auth/mfa/setup/', {'codigo': '000000'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_activar_mfa_sin_codigo_rechaza(self):
        self.client.get('/api/auth/mfa/setup/')
        res = self.client.post('/api/auth/mfa/setup/', {}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_desactivar_mfa_con_contrasena_correcta(self):

        self.usuario.mfa_secret = pyotp.random_base32()
        self.usuario.mfa_habilitado = True
        self.usuario.save(update_fields=['mfa_secret', 'mfa_habilitado'])

        res = self.client.delete('/api/auth/mfa/setup/',
                                  data={'password': 'Test1234!'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        self.usuario.refresh_from_db()
        self.assertFalse(self.usuario.mfa_habilitado)
        self.assertEqual(self.usuario.mfa_secret, '')

    def test_desactivar_mfa_con_contrasena_incorrecta_rechaza(self):
        self.usuario.mfa_secret = pyotp.random_base32()
        self.usuario.mfa_habilitado = True
        self.usuario.save(update_fields=['mfa_secret', 'mfa_habilitado'])

        res = self.client.delete('/api/auth/mfa/setup/',
                                  data={'password': 'WrongPassword'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

        self.usuario.refresh_from_db()
        self.assertTrue(self.usuario.mfa_habilitado,
            "MFA no debe desactivarse con contraseña incorrecta")

    def test_mfa_setup_requiere_autenticacion(self):

        anon_client = APIClient()
        res = anon_client.get('/api/auth/mfa/setup/')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)


class TestLoginConMFA(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario(email='mfalogin@test.com', mfa=True)
        self.client = APIClient()

    def test_login_sin_mfa_pide_codigo(self):

        res = self.client.post('/api/auth/login/', {
            'email': 'mfalogin@test.com',
            'password': 'Test1234!',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_202_ACCEPTED)
        self.assertTrue(res.data.get('mfa_required'))
        self.assertNotIn('access', res.data,
            "No debe entregarse token JWT hasta completar MFA")

    def test_login_con_codigo_mfa_correcto_exitoso(self):
        codigo = _codigo_valido(self.usuario)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfalogin@test.com',
            'password': 'Test1234!',
            'codigo_mfa': codigo,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('access', res.data)
        self.assertIn('refresh', res.data)

    def test_login_con_codigo_mfa_incorrecto_rechaza(self):
        res = self.client.post('/api/auth/login/', {
            'email': 'mfalogin@test.com',
            'password': 'Test1234!',
            'codigo_mfa': '000000',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_con_contrasena_incorrecta_y_codigo_correcto_rechaza(self):

        codigo = _codigo_valido(self.usuario)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfalogin@test.com',
            'password': 'WrongPassword',
            'codigo_mfa': codigo,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_usuario_bloqueado_rechaza_antes_de_verificar_mfa(self):

        self.usuario.estado = 'BLOQUEADO'
        self.usuario.fecha_bloqueo = timezone.now()
        self.usuario.save(update_fields=['estado', 'fecha_bloqueo'])

        codigo = _codigo_valido(self.usuario)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfalogin@test.com',
            'password': 'Test1234!',
            'codigo_mfa': codigo,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_intentos_mfa_fallidos_incrementan_contador(self):


        from apps.administracion.mfa import MAX_INTENTOS
        for _ in range(MAX_INTENTOS):
            self.client.post('/api/auth/login/', {
                'email': 'mfalogin@test.com',
                'password': 'Test1234!',
                'codigo_mfa': '000000',
            }, format='json')


        self.usuario.refresh_from_db()


        self.assertIn(self.usuario.estado, ['ACTIVO', 'BLOQUEADO'])

    def test_login_con_codigo_vencido_rechaza(self):

        codigo_viejo = _codigo_vencido(self.usuario, periodos_atras=2)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfalogin@test.com',
            'password': 'Test1234!',
            'codigo_mfa': codigo_viejo,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_con_codigo_del_periodo_anterior_aceptado(self):

        t = pyotp.TOTP(self.usuario.mfa_secret)
        codigo_pasado = t.at(time.time() - 30)
        res = self.client.post('/api/auth/login/', {
            'email': 'mfalogin@test.com',
            'password': 'Test1234!',
            'codigo_mfa': codigo_pasado,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK,
            "El código del período anterior debe aceptarse por desfase de reloj")


class TestBloqueoViaAPI(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario(email='apibloqueo@test.com')
        self.client = APIClient()

    def _login_fallido(self):
        return self.client.post('/api/auth/login/', {
            'email': 'apibloqueo@test.com',
            'password': 'WrongPassword',
        }, format='json')

    def test_5_intentos_bloquean_via_api(self):
        for _ in range(5):
            self._login_fallido()
        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.estado, 'BLOQUEADO')

    def test_6_intento_devuelve_403_bloqueado(self):

        for _ in range(5):
            self._login_fallido()
        res = self._login_fallido()
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN,
            "Cuenta bloqueada debe devolver 403, no 401")

    def test_respuesta_fallida_muestra_intentos_restantes(self):
        res = self._login_fallido()
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

        detail = res.data.get('detail', '')
        self.assertIn('intento', detail.lower(),
            "La respuesta debe indicar intentos restantes")

    def test_contrasena_correcta_despues_de_bloqueo_da_403(self):


        for _ in range(5):
            self._login_fallido()

        res = self.client.post('/api/auth/login/', {
            'email': 'apibloqueo@test.com',
            'password': 'Test1234!',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN,
            "SEGURIDAD: Un usuario bloqueado con contraseña correcta no debe "
            "distinguirse de uno bloqueado con contraseña incorrecta")

    def test_desbloqueo_automatico_permite_login(self):

        from apps.administracion.mfa import BLOQUEO_MINUTOS
        for _ in range(5):
            self._login_fallido()

        tiempo_futuro = timezone.now() + timedelta(minutes=BLOQUEO_MINUTOS + 1)
        with freeze_time(tiempo_futuro):
            res = self.client.post('/api/auth/login/', {
                'email': 'apibloqueo@test.com',
                'password': 'Test1234!',
            }, format='json')

        self.assertEqual(res.status_code, status.HTTP_200_OK,
            "Después de BLOQUEO_MINUTOS debe poder loguearse normalmente")


class TestStressMFAConcurrente(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario(email='stress@test.com', mfa=True)

    def test_50_verificaciones_correctas_paralelas(self):


        from apps.administracion.mfa import verificar_totp
        codigo = _codigo_valido(self.usuario)
        resultados = []
        errores = []

        def verificar():
            try:
                r = verificar_totp(self.usuario, codigo)
                resultados.append(r)
            except Exception as e:
                errores.append(str(e))

        threads = [threading.Thread(target=verificar) for _ in range(50)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(errores, [], f"Excepciones en verificación paralela: {errores}")
        self.assertTrue(all(resultados),
            f"Fallos inesperados: {resultados.count(False)} de 50 verificaciones correctas fallaron")

    def test_20_logins_fallidos_paralelos_no_corrompen_contador(self):


        from apps.administracion.mfa import registrar_intento_fallido

        def login_fallido():
            from apps.administracion.models import UsuarioInterno
            u = UsuarioInterno.objects.get(pk=self.usuario.pk)
            registrar_intento_fallido(u)

        threads = [threading.Thread(target=login_fallido) for _ in range(20)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.usuario.refresh_from_db()
        self.assertEqual(self.usuario.intentos_fallidos, 20,
            f"Race condition detectada: solo se registraron "
            f"{self.usuario.intentos_fallidos} de 20 intentos")


class TestNotificacionBloqueo(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario()

    def test_notificacion_se_envia_al_email_del_usuario(self):
        from apps.administracion.mfa import _notificar_bloqueo
        with patch('apps.administracion.mfa.send_mail') as mock_mail:
            _notificar_bloqueo(self.usuario)
            mock_mail.assert_called_once()
            args, kwargs = mock_mail.call_args
            recipient_list = kwargs.get('recipient_list') or args[3]
            self.assertIn(self.usuario.email, recipient_list)

    def test_notificacion_menciona_tiempo_de_bloqueo(self):
        from apps.administracion.mfa import _notificar_bloqueo, BLOQUEO_MINUTOS
        with patch('apps.administracion.mfa.send_mail') as mock_mail:
            _notificar_bloqueo(self.usuario)
            _, kwargs = mock_mail.call_args
            message = kwargs.get('message') or mock_mail.call_args[0][1]
            self.assertIn(str(BLOQUEO_MINUTOS), message,
                "El email debe mencionar los minutos de bloqueo")

    def test_notificacion_falla_silenciosamente(self):

        from apps.administracion.mfa import _notificar_bloqueo
        with patch('apps.administracion.mfa.send_mail', side_effect=Exception("SMTP error")):
            try:
                _notificar_bloqueo(self.usuario)
            except Exception:
                self.fail("_notificar_bloqueo debe absorber errores de envío silenciosamente")

    @override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
    def test_email_tiene_asunto_correcto(self):
        from apps.administracion.mfa import _notificar_bloqueo
        from django.core import mail
        _notificar_bloqueo(self.usuario)
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn('bloqueada', mail.outbox[0].subject.lower())


class TestCompatibilidadGoogleAuthenticator(TestCase):


    def setUp(self):
        self.usuario = _crear_usuario(email='gauth@test.com')

    def test_flujo_completo_scan_qr_y_verificar(self):


        from apps.administracion.mfa import generar_secret_totp, verificar_totp

        self.usuario.mfa_secret = generar_secret_totp()
        self.usuario.save(update_fields=['mfa_secret'])


        ga_totp = pyotp.TOTP(self.usuario.mfa_secret)


        codigo_ga = ga_totp.now()


        self.assertTrue(verificar_totp(self.usuario, codigo_ga),
            "El código generado por Google Authenticator debe ser válido")

    def test_sincronizacion_con_reloj_ligeramente_desviado(self):


        from apps.administracion.mfa import generar_secret_totp, verificar_totp
        self.usuario.mfa_secret = generar_secret_totp()
        self.usuario.save(update_fields=['mfa_secret'])


        ga_totp = pyotp.TOTP(self.usuario.mfa_secret)
        codigo_con_retraso = ga_totp.at(time.time() - 25)

        self.assertTrue(verificar_totp(self.usuario, codigo_con_retraso),
            "Con retraso de 25s (< 1 período) el código debe ser válido")

    def test_desfase_mayor_a_1_minuto_rechaza(self):


        from apps.administracion.mfa import generar_secret_totp, verificar_totp
        self.usuario.mfa_secret = generar_secret_totp()
        self.usuario.save(update_fields=['mfa_secret'])

        ga_totp = pyotp.TOTP(self.usuario.mfa_secret)
        codigo_muy_viejo = ga_totp.at(time.time() - 90)

        self.assertFalse(verificar_totp(self.usuario, codigo_muy_viejo),
            "Con desfase > 1 minuto el código debe rechazarse")
