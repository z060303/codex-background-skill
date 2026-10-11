"""Package the verified, archived dependency with its license; never execute it."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = 'f307ce1a3fd9fba9b257636805378465416d9884d6e2067a0c5f43a46c17ffe6'
EXE = '77813ada548253fe0376b8e06ff6e090d7cc0e77094e4eead1e981fbc0734019'
COMMIT = 'eccfd6d3b4d38ba9526b1c66409fc47bb7168b5e'


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--upstream-zip', type=Path, required=True)
    p.add_argument('--source', type=Path, required=True)
    args = p.parse_args()
    if sha(args.upstream_zip.read_bytes()) != ORIGINAL: raise SystemExit('Unexpected upstream archive hash')
    actual = subprocess.check_output(['git','-C',str(args.source),'rev-parse','v1.6.1^{commit}'], text=True).strip()
    if actual != COMMIT: raise SystemExit('Unexpected source commit')
    dist = ROOT/'dist'
    dist.mkdir(exist_ok=True)
    license_text = subprocess.check_output(['git','-C',str(args.source),'show',COMMIT+':LICENSE'])
    (ROOT/'skills/codex-background/assets/CODEFACE-LICENSE.txt').write_bytes(license_text)
    source_name = 'CodeFace-v1.6.1-source.zip'
    subprocess.run(['git','-C',str(args.source),'archive','--format=zip','--prefix=CodeFace-1.6.1/','--output='+str(dist/source_name),COMMIT],check=True)
    archive_name = 'CodeFace-v1.6.1-windows-x64-archive.zip'
    with zipfile.ZipFile(args.upstream_zip) as original, zipfile.ZipFile(dist/archive_name, 'w', compression=zipfile.ZIP_DEFLATED) as target:
        if sha(original.read('CodeFace.exe')) != EXE: raise SystemExit('Unexpected executable hash')
        payload = {name:original.read(name) for name in ['CodeFace.exe','CodeFace.ico']}
        payload['LICENSE.txt'] = license_text
        payload['PROVENANCE.md'] = (ROOT/'THIRD_PARTY_NOTICES.md').read_bytes()
        for name,data in payload.items():
            info = zipfile.ZipInfo(name, date_time=(2026,10,11,0,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info,data)
    manifest = {
        'version':'1.6.1', 'sourceCommit':COMMIT,
        'url':'https://github.com/z060303/codex-background-skill/releases/download/v1.0.0/'+archive_name,
        'archiveSha256':sha((dist/archive_name).read_bytes()), 'exeSha256':EXE,
        'sourceUrl':'https://github.com/z060303/codex-background-skill/releases/download/v1.0.0/'+source_name,
    }
    (ROOT/'skills/codex-background/assets/runtime.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(manifest,indent=2))


if __name__ == '__main__': main()
