import os
import sys
import json
import urllib.request
import urllib.error
import urllib.parse

def upload_to_release(tag, file_path, asset_name):
    token = os.environ.get('GITHUB_TOKEN')
    repo = os.environ.get('GITHUB_REPOSITORY', 'Sanjuantony2255/manjalydentalcare')
    if not token:
        print("No GITHUB_TOKEN provided, skipping upload.")
        return False

    if not os.path.isfile(file_path):
        print(f"File not found: {file_path}")
        return False

    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'GitHub-Release-Uploader'
    }

    # 1. Get or create release for tag
    rel_url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
    release_id = None
    try:
        req = urllib.request.Request(rel_url, headers=headers)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            release_id = data.get('id')
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"Release {tag} does not exist. Creating...")
            create_url = f"https://api.github.com/repos/{repo}/releases"
            create_payload = json.dumps({
                'tag_name': tag,
                'name': f"Release {tag}",
                'body': "## 🦷 Manjaly Dental Care - Android Release APK\n\nDownload the APK below to install on Android.",
                'make_latest': "true"
            }).encode()
            req = urllib.request.Request(create_url, data=create_payload, headers={**headers, 'Content-Type': 'application/json'})
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode())
                release_id = data.get('id')
        else:
            print(f"Error fetching release {tag}: {e}")
            return False

    if not release_id:
        print(f"Could not get release_id for {tag}")
        return False

    print(f"Targeting release ID {release_id} for tag {tag}")

    # 2. Check if asset already exists and delete it
    assets_url = f"https://api.github.com/repos/{repo}/releases/{release_id}/assets"
    req = urllib.request.Request(assets_url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            existing_assets = json.loads(resp.read().decode())
            for a in existing_assets:
                if a.get('name') == asset_name:
                    del_url = f"https://api.github.com/repos/{repo}/releases/assets/{a['id']}"
                    del_req = urllib.request.Request(del_url, headers=headers, method='DELETE')
                    with urllib.request.urlopen(del_req) as del_resp:
                        print(f"Deleted existing asset {asset_name} (ID: {a['id']})")
    except Exception as ex:
        print(f"Error checking/deleting existing assets: {ex}")

    # 3. Upload the asset
    enc_name = urllib.parse.quote(asset_name)
    upload_url = f"https://uploads.github.com/repos/{repo}/releases/{release_id}/assets?name={enc_name}"
    with open(file_path, 'rb') as f:
        apk_data = f.read()

    up_headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/vnd.android.package-archive',
        'Content-Length': str(len(apk_data)),
        'User-Agent': 'GitHub-Release-Uploader'
    }
    up_req = urllib.request.Request(upload_url, data=apk_data, headers=up_headers)
    try:
        with urllib.request.urlopen(up_req) as up_resp:
            res_json = json.loads(up_resp.read().decode())
            print(f"Successfully uploaded {asset_name} -> {res_json.get('browser_download_url')}")
            return True
    except urllib.error.HTTPError as he:
        print(f"Upload HTTPError {he.code}: {he.read().decode()}")
        return False
    except Exception as e:
        print(f"Upload failed: {e}")
        return False

if __name__ == '__main__':
    apk_path = sys.argv[1] if len(sys.argv) > 1 else 'dist/Manjaly-Dental-Care-v1.0.1.apk'
    if not os.path.isfile(apk_path):
        # Search for any release apk
        for candidate in ['dist/Manjaly-Dental-Care-v1.0.1.apk', 'dist/Manjaly-Dental-Care-v1.0.0.apk', 'dental_care_app/build/app/outputs/flutter-apk/app-release.apk']:
            if os.path.isfile(candidate):
                apk_path = candidate
                break

    print(f"Selected APK: {apk_path} ({os.path.getsize(apk_path)} bytes)")
    # Upload to v1.0.1
    upload_to_release('v1.0.1', apk_path, 'Manjaly-Dental-Care-v1.0.1.apk')
    upload_to_release('v1.0.1', apk_path, 'Manjaly-Dental-Care.apk')
    # Also update v1.0.0 release asset so users clicking the old v1.0.0 link get the fresh APK
    upload_to_release('v1.0.0', apk_path, 'Manjaly-Dental-Care-v1.0.0.apk')
