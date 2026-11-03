from pathlib import Path
import json,numpy as np
P=Path(__file__).resolve().parents[1]
NOTES=json.loads((P/'analysis/shared32_piano_parameters.json').read_text());N=1000
C4=[11506414,12190621,12915513,13683509,14497173,15359220,16272527,17240142,18265294,19351405,20502099,21721217]
class Model:
 def __init__(self):
  self.e=np.zeros((12,40),dtype=np.int64);self.p=np.zeros((12,40),dtype=np.int64);self.init=[False]*12;self.age=[0]*12
  self.ng=[0]*12;self.ns=[0xace1^(k*0xf35) for k in range(12)];self.np=[0]*12
 def tick(self,trig,gate,octs,vib):
  out=[];active=0
  for k in range(12):
   n=NOTES[(octs[k]-3)*12+k];restart=bool(trig>>k&1) or (not self.init[k] and bool(gate>>k&1))
   self.age[k]=0 if restart else min(65535,self.age[k]+1)
   if restart:
    self.ng[k]=(n['amplitude'][0]<<5) if gate>>k&1 else 0;self.ns[k]=0xace1^(k*0xf35);self.np[k]=0
   acc=0;anyenergy=False
   for m in range(40):
    E=(n['amplitude'][m]<<10) if restart and gate>>k&1 else 0 if restart else int(self.e[k,m]) if self.init[k] else 0
    step=n['increment'][m];actual=(step+(((step>>8)*vib)>>8))&0xffffffff
    phase=((n['phase'][m]<<26) if restart else int(self.p[k,m]) if self.init[k] else 0)+actual;phase&=0xffffffff
    sine=round(np.sin((phase>>22)*(2*np.pi/1024))*32767)
    acc+=(sine*(E>>10))>>15
    loss=((E*(n['decay'][m]))>>20)+1
    nextE=0 if E<=1024 or loss>=E or step>>31 else E-loss
    self.e[k,m]=nextE;self.p[k,m]=phase;anyenergy|=nextE!=0
   diff=(self.ns[k]>>8)-self.np[k]
   value=(((acc*min(self.age[k],64))>>6)+((diff*(self.ng[k]>>10))>>8))<<4
   if anyenergy or self.ng[k]>1024:active|=1<<k
   self.np[k]=self.ns[k]>>8;seed=self.ns[k];self.ns[k]=((seed<<1)|(((seed>>15)^(seed>>13)^(seed>>12)^(seed>>10))&1))&65535
   self.ng[k]=0 if self.ng[k]<=1024 else self.ng[k]-(self.ng[k]>>8)-1;self.init[k]=True;out.append(value)
  return out,active

def main():
 model=Model();rows=[];maxamp=0
 for f in range(N):
  octs=[3 if f<200 else 4 if f<400 else 5 if f<600 else 3+k%3 for k in range(12)]
  gate=0 if f==0 or 600<=f<700 or f>=900 else 0xfff if f<800 else 0x555
  trig=0xfff if f in [1,200,400,700] else 0x555 if f in [801,820,850] else 0
  vib=0 if f<700 else 1900 if f<800 else -1900
  values,act=model.tick(trig,gate,octs,vib);maxamp=max(maxamp,max(abs(x) for x in values))
  packed=trig;packed=(packed<<12)|gate;packed=(packed<<48)|sum(o<<(k*4) for k,o in enumerate(octs));packed=(packed<<16)|(vib&65535);packed=(packed<<12)|act
  packed=(packed<<288)|sum((v&0xffffff)<<(24*k) for k,v in enumerate(values));rows.append(f'{packed:097x}\n')
 (P/'analysis/shared32_piano_vectors.hex').write_text(''.join(rows));print('Generated',N,'bit-exact frames; raw peak',maxamp)
if __name__=='__main__':main()
