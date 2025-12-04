import os
import json
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from urllib.request import urlopen
from jose import jwt

# --- CONFIGURACIÓN DE SEGURIDAD ---
AUTH0_DOMAIN = os.environ.get('AUTH0_DOMAIN')
API_AUDIENCE = os.environ.get('AUTH0_AUDIENCE')
ALGORITHMS = ["RS256"]

def get_token_auth_header(request):
    """Obtiene el token del header Authorization"""
    auth = request.headers.get("Authorization", None)
    if not auth:
        return None
    parts = auth.split()
    if parts[0].lower() != "bearer":
        return None
    if len(parts) == 1 or len(parts) > 2:
        return None
    return parts[1]

def require_auth(f):
    """Decorador para validar el Token y rechazar en <800ms"""
    def wrap(request, *args, **kwargs):
        token = get_token_auth_header(request)
        
        # ASR: Rechazo inmediato si no hay token
        if not token:
            return JsonResponse({"code": "authorization_header_missing", "description": "Authorization header is expected"}, status=401)

        try:
            # En producción, estas llaves se deberían cachear para velocidad
            jsonurl = urlopen(f"https://{AUTH0_DOMAIN}/.well-known/jwks.json")
            jwks = json.loads(jsonurl.read())
            unverified_header = jwt.get_unverified_header(token)

            rsa_key = {}
            for key in jwks["keys"]:
                if key["kid"] == unverified_header["kid"]:
                    rsa_key = {
                        "kty": key["kty"],
                        "kid": key["kid"],
                        "use": key["use"],
                        "n": key["n"],
                        "e": key["e"]
                    }
            
            if rsa_key:
                payload = jwt.decode(
                    token,
                    rsa_key,
                    algorithms=ALGORITHMS,
                    audience=API_AUDIENCE,
                    issuer=f"https://{AUTH0_DOMAIN}/"
                )
            else:
                return JsonResponse({"code": "invalid_header", "description": "Unable to find appropriate key"}, status=401)

        except jwt.ExpiredSignatureError:
            return JsonResponse({"code": "token_expired", "description": "Token is expired"}, status=401)
        except Exception:
            return JsonResponse({"code": "invalid_header", "description": "Unable to parse authentication token"}, status=401)

        return f(request, *args, **kwargs)
    return wrap

# --- VISTA PROTEGIDA (Inventario) ---
@csrf_exempt
@require_auth  # <--- Seguridad Activada
def measure(request):
    if request.method == 'POST':
        # Simula escritura critica en base de datos
        return JsonResponse({"message": "Escritura exitosa en Inventario", "status": "success"}, status=200)
    elif request.method == 'GET':
        return JsonResponse({"message": "Listado de inventario"}, status=200)
    else:
        return JsonResponse({"message": "Metodo no permitido"}, status=405)
