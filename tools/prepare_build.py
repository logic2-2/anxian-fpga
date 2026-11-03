"""Prepare a local V57 r7 build from the frozen recipe; no board access."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OLD_SOURCE = 'E:/FPGA/anxian_contest/project_v57'
OLD_OUTPUT = 'E:/FPGA/anxian_contest/evidence/v57/r7'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    hashes = json.loads((ROOT / 'records/build/source_manifest.json').read_text(encoding='utf-8-sig'))['source_sha256']
    for relative, expected in hashes.items():
        actual = hashlib.sha256((ROOT / 'project_v57' / relative).read_bytes()).hexdigest().upper()
        if actual != expected.upper():
            raise SystemExit('Release source changed: ' + relative)
    output = (args.out or ROOT / 'output' / datetime.datetime.now().strftime('build_%Y%m%d_%H%M%S_%f')).resolve()
    if output.exists():
        raise SystemExit('Choose a new output directory: ' + str(output))
    output.mkdir(parents=True)
    source = output / 'project_v57'
    shutil.copytree(ROOT / 'project_v57', source)
    changed = []
    for path in source.rglob('*'):
        if path.is_file() and path.suffix.lower() in {'.v', '.vh', '.sdc', '.adc', '.tcl', '.ipc'}:
            data = path.read_bytes()
            updated = data.replace(OLD_SOURCE.encode(), source.as_posix().encode())
            if updated != data:
                path.write_bytes(updated)
                changed.append(path.relative_to(source).as_posix())
    recipe = (ROOT / 'records/build/original_build.tcl').read_text(encoding='utf-8')
    recipe = recipe.replace(OLD_SOURCE, source.as_posix()).replace(OLD_OUTPUT, output.as_posix())
    recipe = re.sub(r'(?m)^(read_adc|read_sdc|report_timing_exception -file) ([^\n{]+)$',
                    lambda m: m[1] + ' {' + m[2].strip() + '}', recipe)
    script = output / 'build.tcl'
    script.write_text(recipe, encoding='utf-8')
    inputs = re.findall(r'(?m)^(?:analyze -file|source|read_adc|read_sdc) \{([^}]+)\}', recipe)
    missing = [item for item in inputs if not Path(item).is_file() and Path(item).is_absolute()]
    # Validate every relocated include/ROM data path, including encrypted-IP wrappers.
    for path in source.rglob('*'):
        if path.is_file() and path.suffix.lower() in {'.v', '.vh'}:
            text = path.read_text(encoding='utf-8', errors='replace')
            for item in re.findall(r'"(' + re.escape(source.as_posix()) + r'/[^"\r\n]+)"', text):
                if not Path(item).is_file():
                    missing.append(item)
    if missing:
        raise SystemExit('Missing dependency: ' + ', '.join(sorted(set(missing))))
    report = {'source_version': 'V57 r7', 'build_script': str(script),
              'frozen_source_hashes_verified': len(hashes), 'build_input_count': len(inputs),
              'path_only_modified_copies': changed, 'missing_dependencies': [],
              'board_accessed': False}
    (output / 'preparation_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('Prepared: ' + str(script))
    print('Verified frozen sources: ' + str(len(hashes)) + '; build dependencies: ' + str(len(inputs)))
    print('Run build.tcl with TD 6.2.168.116 td_commands_prompt.exe. No programming is performed by this script.')


if __name__ == '__main__':
    main()
