"""Run Icarus preprocessor and compiler backend without the Windows driver.

This avoids the iverilog.exe driver cleanup crash seen in the sandbox.
Both real compiler stages must return zero; generated output alone is never
treated as successful compilation. Normal installations can use iverilog.
"""
import argparse
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--bin', required=True)
p.add_argument('--top', required=True)
p.add_argument('--output', required=True)
p.add_argument('sources', nargs='+')
a = p.parse_args()
base = Path(a.bin).parent / 'lib' / 'ivl'
out = Path(a.output)
files = out.with_suffix('.files')
preprocessed = out.with_suffix('.preprocessed.v')
defines = out.with_suffix('.defines')
config = out.with_suffix('.conf')
files.write_text(''.join(str(Path(s).absolute())+'\n' for s in a.sources),encoding='utf-8')
with preprocessed.open('wb') as stream:
    subprocess.run([str(base/'ivlpp.exe'), '-L', '-f', str(files), '-p', str(defines)],
                   stdout=stream, check=True)
lines = [f'root:{a.top}', f'basedir:{base}', 'generation:2012',
         'generation:no-specify', 'generation:assertions', 'generation:xtypes',
         'generation:io-range-error', 'generation:icarus-misc',
         'warnings:n', 'ignore_missing_modules:false', f'out:{out}',
         'iwidth:32', 'widthcap:65536']
for module in ['system','vhdl_sys','vhdl_textio','v2005_math','va_math','v2009']:
    if (base/(module+'.vpi')).exists(): lines.append(f'module:{base/(module+".vpi")}')
config.write_text('\n'.join(lines)+'\n',encoding='utf-8')
subprocess.run([str(base/'ivl.exe'), '-C', str(config), '-C', str(base/'vvp.conf'),
                str(preprocessed)], check=True)
assert out.exists() and out.stat().st_size > 0
print(f'COMPILE PASS {a.top}: ivlpp=0, ivl=0')
