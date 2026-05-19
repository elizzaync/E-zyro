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

logging.warning(
    f"[Cloudinary] cloud={_cloud_name!r}  key={_api_key[:6]}...  "
    f"secret={_api_secret[:4]}...{_api_secret[-4:] if len(_api_secret) > 8 else '(vacío)'}"
)

cloudinary.config(
    cloud_name        = _cloud_name,
    api_key           = _api_key,
    api_secret        = _api_secret,
    secure            = True,
    signature_algorithm = "sha1",
)
cloudinary_uploader = cloudinary.uploader