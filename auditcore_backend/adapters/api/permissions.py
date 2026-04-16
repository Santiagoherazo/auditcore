from rest_framework.permissions import BasePermission

ROLES_PERSONAL = frozenset(['SUPERVISOR', 'ASESOR', 'AUDITOR', 'AUXILIAR', 'REVISOR'])
ROLES_AUDITORES = frozenset(['SUPERVISOR', 'AUDITOR'])
ROLES_CHATBOT   = frozenset(['SUPERVISOR', 'ASESOR', 'AUDITOR', 'AUXILIAR', 'REVISOR'])
ROLES_CLIENTES  = frozenset(['CLIENTE'])


def _rol(request) -> str:
    return getattr(request.user, 'rol', '') or ''


class IsSupervisor(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) == 'SUPERVISOR')


class IsSupervisorOrAsesor(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ('SUPERVISOR', 'ASESOR'))


class IsSupervisorOrAuditor(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ('SUPERVISOR', 'AUDITOR'))


class IsAuditTeam(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ROLES_AUDITORES)


class IsPersonalInterno(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ROLES_PERSONAL)


class IsRevisorOrAbove(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ('SUPERVISOR', 'REVISOR', 'AUDITOR'))


class CanCreateClientes(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ('SUPERVISOR', 'ASESOR'))


class CanAudit(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ('SUPERVISOR', 'AUDITOR'))


class CanCreateProcedimientos(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ('SUPERVISOR', 'AUDITOR', 'AUXILIAR'))


class CanUseChatbot(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) in ROLES_CHATBOT)

    def has_object_permission(self, request, view, obj):
        if _rol(request) == 'SUPERVISOR':
            return True
        usuario_id = getattr(obj, 'usuario_interno_id', None)
        return usuario_id and str(usuario_id) == str(request.user.id)


class IsClientePortal(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated
                    and _rol(request) == 'CLIENTE')


class HasPermission(BasePermission):
    def has_permission(self, request, view):
        permiso = getattr(view, 'required_permission', None)
        if not permiso:
            return bool(request.user and request.user.is_authenticated)
        return bool(request.user and request.user.is_authenticated
                    and request.user.tiene_permiso(permiso))


# Aliases de compatibilidad para vistas existentes
IsAdmin        = IsSupervisor
IsAdminOrLider = IsSupervisorOrAuditor
IsInternalUser = IsPersonalInterno
IsExecutivoOrAdmin = IsSupervisorOrAsesor
