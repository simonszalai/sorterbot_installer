"""
Uploads a GitHub secret to be used in GitHub Actions utilizing the GitHub API.

CLI arguments:

1: GitHub Personal Auth token
2: Secret name
3: Secret value

"""

import sys
import requests
from base64 import b64encode
from nacl import encoding, public


def encrypt(public_key, secret_value):
    """
    Encrypt a Unicode string using the public key.
    """

    public_key = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
    sealed_box = public.SealedBox(public_key)
    encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))

    return b64encode(encrypted).decode("utf-8")


response = requests.get(
    headers={"Authorization": f"token {sys.argv[1]}"},
    url="https://api.github.com/repos/simonszalai/sorterbot_cloud/actions/secrets/public-key",
)

requests.put(
    headers={"Authorization": f"token {sys.argv[1]}"},
    url=f"https://api.github.com/repos/simonszalai/sorterbot_cloud/actions/secrets/{sys.argv[2]}",
    json={
        "encrypted_value": encrypt(response.json()["key"], sys.argv[3]),
        "key_id": response.json()["key_id"]
    }
)
