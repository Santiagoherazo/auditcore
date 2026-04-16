from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import UsuarioInterno


@admin.register(UsuarioInterno)
class UsuarioInternoAdmin(UserAdmin):
    model = UsuarioInterno
    list_display  = ('email', 'nombre', 'apellido', 'rol', 'estado', 'mfa_habilitado', 'ultimo_acceso')
    list_filter   = ('rol', 'estado', 'mfa_habilitado')
    search_fields = ('email', 'nombre', 'apellido')
    ordering      = ('email',)

    fieldsets = (
        (None,          {'fields': ('email', 'password')}),
        ('Información', {'fields': ('nombre', 'apellido', 'telefono')}),
        ('Acceso',      {'fields': ('rol', 'estado', 'mfa_habilitado')}),
        ('Permisos',    {'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),
    )
    add_fieldsets = (
        (None, {'classes': ('wide',), 'fields': ('email', 'nombre', 'apellido', 'rol', 'password1', 'password2')}),
    )