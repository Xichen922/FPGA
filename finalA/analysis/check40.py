"""Parameter preservation, range, and short all-note model comparisons."""
from pathlib import Path
import json,re,csv
import numpy as np
import compare_51_53 as audio
P=Path(__file__).resolve().parents[1];FS=50000000/512
old=audio.OLD;new=audio.NEW;box=audio.BOX;ratios=audio.RATIOS
for a,b in zip(old,new):
 for field in ['increment','amplitude','decay','phase']:
  assert a[field]==b[field][:32],(field,b['o'],b['k'])
 assert len(b['increment'])==40 and len(set(b['increment']))==40
 assert min(b['amplitude'])>0 and min(b['decay'])>0
 assert min(b['increment'])>0 and max(b['increment'])<2**31
rows=[];levels=[]
for o in range(3,6):
 for k in range(12):
  n=new[(o-3)*12+k];bp=next(b['values'] for b in box if b['lane']==k//3 and b['bank']==(o-3)*3+k%3)
  base=audio.ref.C4[k]>>(4-o) if o<=4 else audio.ref.C4[k]<<(o-4)
  for m in range(40):
   assert bp[m]&0xffffff and bp[m]>>24
   if m<32:
    oldsrc=(audio.R/'src/shared32_parameters.v').read_text()
    chunk=re.split(r'if\(LANE==\d\)begin: bank\d',oldsrc)[1+k//3]
    oldb={int(a):int(v,16) for a,v in re.findall(r"b\[(\d+)\]=36'h([0-9a-f]+)",chunk)}
    assert oldb[((o-3)*3+k%3)*32+m]==bp[m]
   rows.append([o,k,m,n['increment'][m]*FS/2**32,n['amplitude'][m],n['decay'][m],
    (((base>>8)*round(ratios[m]*4096))>>4)*FS/2**32,bp[m]&0xffffff,bp[m]>>24,(base*(m+1))*FS/2**32])
  for name,render in [('piano',audio.piano),('musicbox',audio.musicbox)]:
   a,_=render(o,k,round(FS*.25),False);b,_=render(o,k,round(FS*.25),True)
   assert np.max(np.abs(b))<8388607
   levels.append(dict(instrument=name,octave=o,key=k,peak=int(np.max(np.abs(b))),
      relative_waveform_RMS=float(np.linalg.norm(b-a)/np.linalg.norm(a.astype(float))),
      level_delta_dB=float(20*np.log10(np.linalg.norm(b.astype(float))/np.linalg.norm(a.astype(float))))))
  print('checked',o,k,flush=True)
with (P/'analysis/parameters40.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['octave','pitch_class','mode','piano_hz','piano_amplitude','piano_decay_Q20','musicbox_hz','musicbox_energy','musicbox_decay_Q24','wind_hz']);w.writerows(rows)
(P/'verification/all_notes_MODEL.json').write_text(json.dumps(levels,indent=2))
print('PASS original32 piano/musicbox constants preserved exactly;40 positive independent modes;36-note model range,raw peaks and deltas')
