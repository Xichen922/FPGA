"""Offline fixed-point models only: not RTL audio or board recordings."""
from pathlib import Path
import json,re,importlib.util,wave
import numpy as np
P=Path(__file__).resolve().parents[1]
R=P/'sim/reference_audio51'
spec=importlib.util.spec_from_file_location('reference_audio',R/'analysis/compare_modal_audio.py')
ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
OLD=json.loads((R/'analysis/shared32_piano_parameters.json').read_text())
NEW=json.loads((P/'analysis/shared32_piano_parameters.json').read_text())
BOX=json.loads((P/'analysis/musicbox40_parameters.json').read_text())
RATIOS=json.loads((P/'analysis/shared32_musicbox_ratios.json').read_text())
FS=ref.FS
def piano(o,k,n,new):
 ref.NEW=NEW if new else OLD
 return ref.piano(o,k,n,True)
def musicbox(o,k,n,new):
 if not new:return ref.musicbox(o,k,n,True)
 t=np.arange(n,dtype=np.int64);acc=np.zeros(n,dtype=np.int64);levels=[]
 base=ref.C4[k]>>(4-o) if o<=4 else ref.C4[k]<<(o-4)
 params=next(b['values'] for b in BOX if b['lane']==k//3 and b['bank']==(o-3)*3+k%3)
 for m,param in enumerate(params):
  e=ref.envelope(param&0xffffff,param>>24,n,24,256,box=True)
  seed=ref.SEEDS[m] if m<7 else (0x9e3779b9*m)&0xffffffff
  step=((base>>8)*round(RATIOS[m]*4096))>>4
  phase=(seed+step*(t+1))&0xffffffff
  component=(ref.BT[phase>>21]*(e>>8)+16384)>>15;acc+=component
  levels.append(float(np.sqrt(np.mean(component[:4883].astype(float)**2))))
 age=np.minimum(t,1023);attack=np.array([ref.BOX[256+(128 if o>=5 else 0)+int(i>>3)]&65535 for i in age],dtype=np.int64)
 return ((acc*attack+16384)>>15)<<4,levels
def main():
 stats=[];n=round(FS*1.5);gap=np.zeros(round(FS*.2))
 for name,fn in [('piano',piano),('musicbox',musicbox)]:
  sequence=[]
  for label,o,k in [('C3',3,0),('C4',4,0),('E4',4,4),('G4',4,7),('C5',5,0)]:
   a,_=fn(o,k,n,False);b,levels=fn(o,k,n,True)
   gain=.65*8388607/max(1,np.max(np.abs(a)))
   sequence.extend([a*gain,gap,b*gain,gap])
   stats.append(dict(instrument=name,note=label,relative_waveform_RMS=float(np.linalg.norm(b-a)/np.linalg.norm(a.astype(float))),
       level_delta_dB=float(20*np.log10(np.linalg.norm(b.astype(float))/np.linalg.norm(a.astype(float)))),
       first_50ms_per_mode_RMS=levels,source='offline fixed-point model, not RTL/board'))
   print(name,label,'51/53 rendered',flush=True)
  ref.wav(P/f'audio/53_{name}_51_then_53_MODEL.wav',np.concatenate(sequence))
 (P/'verification/audition_model_metrics.json').write_text(json.dumps(stats,indent=2))
if __name__=='__main__':main()
