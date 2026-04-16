from django.contrib import admin
from .models import Cliente, ContactoCliente, UsuarioCliente

class ContactoInline(admin.TabularInline):
    model = ContactoCliente
    extra = 1

@admin.register(Cliente)
class ClienteAdmin(admin.ModelAdmin):
    list_display  = ('razon_social', 'nit', 'sector', 'estado', 'pais', 'fecha_creacion')
    list_filter   = ('estado', 'sector', 'pais')
    search_fields = ('razon_social', 'nit', 'email')
    inlines       = [ContactoInline]