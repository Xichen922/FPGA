from pathlib import Path
import argparse,subprocess,sys,os,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[1]
TESTS=['tb53_asymmetric_keys','tb53_end_latency','tb53_envelope_storage','tb53_gain_lane','tb53_mode_coverage','tb53_equivalence32','tb51_piano_vectors','tb51_audio_comparison', 'finalA_top', 'tb_piano_i2s', 'tb47_top_io', 'tb47_touch', 'tb47_light', 'tb47_adc', 'tb_keyboard_matrix', 'tb_matrix_latency', 'tb37_score_packet', 'tb37_timbre_restore', 'tb_organ_context', 'tb_natural_release', 'tb_organ_slow_release']
a=argparse.ArgumentParser();a.add_argument('--bin',required=True);a.add_argument('--only',nargs='+',choices=TESTS);args=a.parse_args()
binary=Path(args.bin).resolve();os.environ['PATH']=str(binary)+os.pathsep+os.environ['PATH']
files=[P/e.attrib['path'] for e in ET.parse(P/'finalA.gprj').findall('./FileList/File') if e.attrib['path'].endswith('.v')]
assert all(f.exists() for f in files)
out=P/'verification';out.mkdir(exist_ok=True)
for name in args.only or TESTS:
 sources=files.copy()
 if name in ('tb53_envelope_storage','tb53_mode_coverage','tb53_equivalence32','tb51_audio_comparison','tb51_wind_debug','tb51_audio_equivalence','tb47_warning_equivalence','tb47_musicbox_equivalence'):sources += sorted((P/'sim/reference51').glob('*.v'))
 if name=='tb53_end_latency':sources+=sorted((P/'sim/latency_B44').glob('*.v'))
 if name!='finalA_top':sources += [P/'sim'/(name+'.sv')]
 with (out/(name+'.log')).open('w',encoding='utf-8') as log:
  commands=[[sys.executable,str(P/'sim/compile_direct.py'),'--bin',str(binary),'--top',name,'--output',str(out/(name+'.vvp'))]+list(map(str,sources))]
  if name!='finalA_top':commands += [[str(binary/'vvp.exe'),'-i',str(out/(name+'.vvp'))]]
  for command in commands:
   r=subprocess.run(command,cwd=P,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);print(r.stdout,flush=True);log.write(r.stdout);log.flush()
   if r.returncode:sys.exit(r.returncode)
print('PASS all requested51 checks')


