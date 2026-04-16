from django.contrib import admin
from .models import Expediente, FaseExpediente, AsignacionEquipo, BitacoraExpediente

class FaseInline(admin.TabularInline):
    model = FaseExpediente
    extra = 0

class EquipoInline(admin.TabularInline):
    model = AsignacionEquipo
    extra = 1

@admin.register(Expediente)
class ExpedienteAdmin(admin.ModelAdmin):
    list_display  = ('numero_expediente','cliente','tipo_auditoria','estado','porcentaje_avance','fecha_apertura')
    list_filter   = ('estado','tipo_auditoria')
    search_fields = ('numero_expediente','cliente__razon_social')
    readonly_fields = ('numero_expediente','porcentaje_avance')
    inlines       = [FaseInline, EquipoInline]

@admin.register(BitacoraExpediente)
class BitacoraAdmin(admin.ModelAdmin):
    list_display = ('expediente','accion','tipo_usuario','fecha')
    readonly_fields = [f.name for f in BitacoraExpediente._meta.fields]

    def has_add_permission(self, r): return False
    def has_change_permission(self, r, obj=None): return False
    def has_delete_permission(self, r, obj=None): return False