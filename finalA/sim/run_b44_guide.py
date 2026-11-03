from pathlib import Path
import argparse,os,subprocess,sys
p=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--bin',required=True)
a=parser.parse_args();binary=Path(a.bin).resolve()
os.environ['PATH']=str(binary)+os.pathsep+os.environ['PATH']
out=p/'verification/tb_a41_b44_guide.vvp';out.parent.mkdir(exist_ok=True)
files=[str(p/'src'/s) for s in ['keyboard_matrix_scan.v','joystick_octave.v',
       'touch_note_control.v','db_controls.v','db_spi_link.v']]
files += [str(f) for f in (p/'sim/b44').glob('*.v')]
files += [str(p/'sim/tb_a41_b44_guide.sv')]
with (p/'verification/tb_a41_b44_guide.log').open('w',encoding='utf-8') as log:
    for cmd in [[sys.executable,str(p/'sim/compile_direct.py'),'--bin',str(binary),
                 '--top','tb_a41_b44_guide','--output',str(out)]+files,
                [str(binary/'vvp.exe'),'-i',str(out)]]:
        r=subprocess.run(cmd,cwd=p,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        print(r.stdout,flush=True);log.write(r.stdout);log.flush()
        if r.returncode:sys.exit(r.returncode)
