#!/usr/bin/env python3
"""Publica las builds de Planaby como fuente para SideStore y LiveContainer.

Lee las releases de GitHub (repo privado, token de solo lectura), descarga los IPA
que falten a PLANABY_PUBLIC/ipa y regenera source.json. Pensado para un timer de systemd.
"""
import json
import os
import shutil
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = os.environ.get("PLANABY_REPO", "A1VAR0W/Planaby")
BASE_URL = os.environ.get("PLANABY_BASE_URL", "https://chat-ink.tail552c89.ts.net/planaby").rstrip("/")
PUBLIC = Path(os.environ.get("PLANABY_PUBLIC", "/srv/planaby/public"))
TOKEN_FILE = Path(os.environ.get("PLANABY_TOKEN_FILE", "/etc/planaby/github-token"))
BUNDLE_ID = "com.alvaro.planaby"
TINT = "#FF7A1A"
KEEP = 5


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """GitHub redirige los assets a un almacenamiento firmado que rechaza la cabecera Authorization."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def github_request(path, token, accept="application/vnd.github+json"):
    return urllib.request.Request(
        f"https://api.github.com{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": accept,
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "planaby-sync",
        },
    )


def download_asset(asset_id, dest, token):
    request = github_request(f"/repos/{REPO}/releases/assets/{asset_id}", token, "application/octet-stream")
    try:
        response = urllib.request.build_opener(NoRedirect).open(request, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code not in (301, 302, 303, 307, 308):
            raise
        location = error.headers["Location"]
        response = urllib.request.urlopen(
            urllib.request.Request(location, headers={"User-Agent": "planaby-sync"}), timeout=300
        )
    partial = dest.with_name(dest.name + ".part")
    with response, open(partial, "wb") as out:
        shutil.copyfileobj(response, out)
    partial.replace(dest)


def write_if_changed(path, content):
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    partial = path.with_name(path.name + ".part")
    partial.write_text(content, encoding="utf-8")
    partial.replace(path)
    return True


def main():
    if not TOKEN_FILE.exists() or not TOKEN_FILE.read_text().strip():
        sys.exit(f"Falta el token de GitHub en {TOKEN_FILE}")
    token = TOKEN_FILE.read_text().strip()

    with urllib.request.urlopen(github_request(f"/repos/{REPO}/releases?per_page=20", token), timeout=30) as response:
        releases = json.load(response)

    builds = []
    for release in releases:
        assets = {asset["name"]: asset for asset in release["assets"]}
        if release["draft"] or "Planaby.ipa" not in assets or "metadata.json" not in assets:
            continue
        builds.append((release, assets))
        if len(builds) == KEEP:
            break
    if not builds:
        print("No hay builds publicadas todavía")
        return

    ipa_dir = PUBLIC / "ipa"
    ipa_dir.mkdir(parents=True, exist_ok=True)
    versions, keep_files = [], set()
    for index, (release, assets) in enumerate(builds):
        meta_path = ipa_dir / f"{release['tag_name']}.json"
        if not meta_path.exists():
            download_asset(assets["metadata.json"]["id"], meta_path, token)
        meta = json.loads(meta_path.read_text(encoding="utf-8"))

        ipa_name = f"Planaby-{meta['build']}.ipa"
        ipa_path = ipa_dir / ipa_name
        if not ipa_path.exists():
            print(f"Descargando {ipa_name}")
            download_asset(assets["Planaby.ipa"]["id"], ipa_path, token)
            if index == 0 and "icon.png" in assets:
                download_asset(assets["icon.png"]["id"], PUBLIC / "icon.png", token)

        keep_files.update({meta_path.name, ipa_name})
        versions.append({
            "version": meta["version"],
            "buildVersion": str(meta["build"]),
            "date": meta["date"],
            "localizedDescription": meta.get("notes", ""),
            "downloadURL": f"{BASE_URL}/ipa/{ipa_name}",
            "size": ipa_path.stat().st_size,
            "minOSVersion": "26.0",
        })

    for stale in ipa_dir.iterdir():
        if stale.name not in keep_files:
            stale.unlink()

    latest = versions[0]
    source = {
        "name": "Planaby",
        "identifier": f"{BUNDLE_ID}.source",
        "subtitle": "Builds personales de Planaby",
        "website": f"{BASE_URL}/",
        "iconURL": f"{BASE_URL}/icon.png",
        "tintColor": TINT,
        "apps": [{
            "name": "Planaby",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "Alvaro",
            "subtitle": "Concentración sin distracciones",
            "localizedDescription": "Temporizador de concentración con Pomodoro, 52/17, Ultradiano, Flowtime y plantillas propias.",
            "iconURL": f"{BASE_URL}/icon.png",
            "tintColor": TINT,
            "category": "productivity",
            # Campos planos para clientes que aún leen el formato antiguo.
            "version": latest["version"],
            "versionDate": latest["date"],
            "versionDescription": latest["localizedDescription"],
            "downloadURL": latest["downloadURL"],
            "size": latest["size"],
            "versions": versions,
            "appPermissions": {
                "entitlements": ["com.apple.security.application-groups"],
                "privacy": {},
            },
        }],
        "news": [],
    }
    if write_if_changed(PUBLIC / "source.json", json.dumps(source, ensure_ascii=False, indent=2) + "\n"):
        print(f"source.json actualizado a {latest['version']} ({latest['buildVersion']})")


if __name__ == "__main__":
    main()
