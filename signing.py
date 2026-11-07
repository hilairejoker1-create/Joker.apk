import base64, json, os, secrets, subprocess, urllib.request
from pathlib import Path

url = os.environ['CALLBACK_URL'].replace('/build-callback', '/build-signing')
headers = {'Content-Type': 'application/json', 'x-build-secret': os.environ['SECRET']}
def call(data):
    request = urllib.request.Request(url, data=json.dumps({'build_id': os.environ['BUILD_ID'], **data}).encode(), headers=headers)
    with urllib.request.urlopen(request) as response:
        return json.load(response)

stored = call({'action': 'get'})
if not stored.get('keystore'):
    password = secrets.token_urlsafe(32)
    subprocess.run(['keytool', '-genkeypair', '-keystore', 'release.keystore', '-alias', 'appmaker', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-storepass', password, '-keypass', password, '-dname', 'CN=Joker Android, O=Joker, C=HT'], check=True, capture_output=True)
    stored = call({'action': 'save', 'keystore': base64.b64encode(Path('release.keystore').read_bytes()).decode(), 'password': password})
Path('release.keystore').write_bytes(base64.b64decode(stored['keystore']))
Path('signing.json').write_text(json.dumps({'password': stored['password']}))