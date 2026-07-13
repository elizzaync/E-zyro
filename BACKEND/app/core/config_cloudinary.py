import cloudinary
import cloudinary.uploader
import logging
from os import getenv
from pathlib import Path
from dotenv import load_dotenv

# Carga explícita del .env desde la raíz del proyecto BACKEND
_env_path = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(dotenv_path=_env_path, override=True)

_cloud_name  = getenv("CLOUD_NAME_CLOUDINARY", "")
_api_key     = getenv("API_KEY_CLOUDINARY", "")
_api_secret  = getenv("API_SECRET_CLOUDINARY", "")

# No loguear NUNCA fragmentos del api_key/secret. Solo confirmar que la config
# quedó presente, sin exponer ningún caracter del material secreto.
logging.info(
    "[Cloudinary] configurado: cloud=%s  credenciales=%s",
    _cloud_name or "(sin cloud_name)",
    "OK" if (_api_key and _api_secret) else "FALTAN",
)

cloudinary.config(
    cloud_name        = _cloud_name,
    api_key           = _api_key,
    api_secret        = _api_secret,
    secure            = True,
    signature_algorithm = "sha1",
)
cloudinary_uploader = cloudinary.uploader