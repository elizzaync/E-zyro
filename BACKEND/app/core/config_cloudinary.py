import cloudinary
import cloudinary.uploader
from os import getenv
from dotenv import load_dotenv
load_dotenv()
cloudinary.config(
    cloud_name = getenv("CLOUD_NAME_CLOUDINARY"),
    api_key = getenv("API_KEY_CLOUDINARY"),
    api_secret = getenv("API_SECRET_CLOUDINARY"),
    secure = True,
    signature_algorithm = "sha1",
)
cloudinary_uploader = cloudinary.uploader