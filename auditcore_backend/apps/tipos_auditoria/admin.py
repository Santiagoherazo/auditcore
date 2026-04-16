from django.contrib import admin
from .models import TipoAuditoria, FaseTipoAuditoria, ChecklistItem, DocumentoRequerido

class FaseInline(admin.TabularInline):
    model = FaseTipoAuditoria
    extra = 1

class ChecklistInline(admin.TabularInline):
    model = ChecklistItem
    extra = 1

class DocInline(admin.TabularInline):
    model = DocumentoRequerido
    extra = 1

@admin.register(TipoAuditoria)
class TipoAuditoriaAdmin(admin.ModelAdmin):
    list_display = ('codigo','nombre','categoria','nivel','activo')
    inlines      = [FaseInline, ChecklistInline, DocInline]