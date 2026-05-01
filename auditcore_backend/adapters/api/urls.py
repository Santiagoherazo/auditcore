from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView, TokenBlacklistView
from adapters.api import views
from adapters.api.views_draft import (
    ClienteDraftCreateView,
    ClienteDraftUpdateView,
    ClienteDraftCommitView,
)
from apps.administracion.views_auth import (
    LoginView, MFASetupView,
    PasswordResetRequestView, PasswordResetConfirmView,
    SetupView, SetupStatusView,
)

router = DefaultRouter()
router.register('usuarios',               views.UsuarioInternoViewSet,       basename='usuario')
router.register('clientes',               views.ClienteViewSet,               basename='cliente')
router.register('clientes-sedes',         views.SedeClienteViewSet,          basename='sede-cliente')
router.register('clientes-contactos',     views.ContactoClienteViewSet,      basename='contacto-cliente')
router.register('tipos-auditoria',        views.TipoAuditoriaViewSet,        basename='tipo-auditoria')
router.register('tipos-auditoria-fases',  views.FaseTipoAuditoriaViewSet,    basename='fase-tipo-auditoria')
router.register('tipos-auditoria-checklist', views.ChecklistItemViewSet,     basename='checklist-item')
router.register('tipos-auditoria-documentos', views.DocumentoRequeridoViewSet, basename='documento-requerido')
router.register('formularios/esquemas',   views.EsquemaFormularioViewSet,    basename='esquema')
router.register('formularios/valores',    views.ValorFormularioViewSet,      basename='valor')
router.register('expedientes',            views.ExpedienteViewSet,            basename='expediente')
router.register('hallazgos',              views.HallazgoViewSet,              basename='hallazgo')
router.register('evidencias',             views.EvidenciaViewSet,             basename='evidencia')
router.register('checklist',              views.ChecklistEjecucionViewSet,    basename='checklist')
router.register('documentos',             views.DocumentoViewSet,             basename='documento')
router.register('certificaciones',        views.CertificacionViewSet,         basename='certificacion')
router.register('chatbot/conversaciones', views.ConversacionViewSet,          basename='conversacion')
router.register('visitas',                views.VisitaAgendadaViewSet,        basename='visita')

urlpatterns = [

    path('auth/login/',          LoginView.as_view(),                name='login'),
    path('auth/refresh/',        TokenRefreshView.as_view(),         name='token-refresh'),
    path('auth/logout/',         TokenBlacklistView.as_view(),       name='token-blacklist'),
    path('auth/mfa/',            MFASetupView.as_view(),             name='mfa-setup'),
    path('auth/password-reset/', PasswordResetRequestView.as_view(), name='password-reset-request'),
    path('auth/password-reset/confirm/', PasswordResetConfirmView.as_view(), name='password-reset-confirm'),


    path('auth/setup/',        SetupView.as_view(),       name='setup'),
    path('auth/setup/status/', SetupStatusView.as_view(), name='setup-status'),


    path('clientes/draft/',                  ClienteDraftCreateView.as_view(),  name='cliente-draft-create'),
    path('clientes/draft/<str:draft_id>/',   ClienteDraftUpdateView.as_view(),  name='cliente-draft-update'),
    path('clientes/draft/<str:draft_id>/commit/', ClienteDraftCommitView.as_view(), name='cliente-draft-commit'),


    path('', include(router.urls)),


    path('chatbot/status/', views.ChatbotStatusView.as_view(), name='chatbot-status'),


    path('chatbot/analizar-documento/', views.AnalizarDocumentoChatbotView.as_view(), name='chatbot-analizar-documento'),


    path('clientes/acceso-temporal/', views.AccesoTemporalView.as_view(), name='acceso-temporal'),
    path('clientes/caracterizacion/<str:token>/', views.CaracterizacionPublicaView.as_view(), name='caracterizacion-publica'),


    path('usuarios/mis-permisos/', views.MisPermisosView.as_view(), name='mis-permisos'),


    path('dashboard/', views.DashboardGlobalView.as_view(), name='dashboard'),


    path('seguridad/bitacora/', views.BitacoraGlobalView.as_view(), name='bitacora-global'),


    path('administracion/seed/', views.SeedDemoView.as_view(), name='seed-demo'),


    path('reportes/exportar/', views.ExportarReporteView.as_view(), name='exportar-reporte'),
]