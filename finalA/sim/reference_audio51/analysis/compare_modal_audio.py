from pathlib import Path
import json,re,wave,csv
import numpy as np

P=Path(__file__).resolve().parents[1]
FS=50000000/512
OLD=json.loads((P/'analysis/piano_parameters.json').read_text(encoding='utf-8'))
NEW=json.loads((P/'analysis/shared32_piano_parameters.json').read_text(encoding='utf-8'))
RATIOS=json.loads((P/'analysis/shared32_musicbox_ratios.json').read_text())
OLD_RATIOS=[4096,8192,12288,25670,50176,71885,25716]
SEEDS=[0,0x0f133d70,0x1e267ae0,0x2d39b850,0x3c4cf5c0,0x4b603330,0x24ab572c]
C4=[11506414,12190621,12915513,13683509,14497173,15359220,16272527,17240142,18265294,19351405,20502099,21721217]
BOX={int(i):int(v,16) for i,v in re.findall(r"values\[(\d+)\]=36'h([0-9a-f]+)",(P/'src/musicbox_parameter_rom.v').read_text())}
PT=np.array([int(v,16) for i,v in re.findall(r"rom\[(\d+)\]=16'h([0-9a-f]+)",(P/'src/piano_synth_sine.v').read_text())],dtype=np.int64)
BT=np.array([int(v,16) for i,v in re.findall(r"values\[(\d+)\]=16'h([0-9a-f]+)",(P/'src/musicbox_sine_rom.v').read_text())],dtype=np.int64)
PT[PT>=32768]-=65536;BT[BT>=32768]-=65536

def envelope(energy,decay,length,shift,threshold,box=False):
    out=np.zeros(length,dtype=np.int64)
    for t in range(length):
        if box and t:energy=0 if energy<=threshold else max(0,energy-((energy*decay)>>shift)-1)
        out[t]=energy
        if not box:energy=0 if energy<=threshold else max(0,energy-((energy*decay)>>shift)-1)
        if energy==0:break
    return out

def piano(o,k,length,new):
    n=(NEW if new else OLD)[(o-3)*12+k];t=np.arange(length,dtype=np.int64);acc=np.zeros(length,dtype=np.int64)
    levels=[]
    for m,amp in enumerate(n['amplitude']):
        e=envelope(amp<<10,n['decay'][m],length,20,1024)
        phase=((n['phase'][m]<<26)+n['increment'][m]*(t+1))&0xffffffff
        component=(PT[phase>>22]*(e>>10))>>15;acc+=component
        levels.append(float(np.sqrt(np.mean(component[:4883].astype(float)**2))))
    acc=(acc*np.minimum(t,64))>>6
    noise=np.zeros(length,dtype=np.int64);state=0xace1^(k*0xf35);previous=0;level=n['amplitude'][0]<<5
    for i in range(length):
        difference=(state>>8)-previous;noise[i]=(difference*(level>>10))>>8
        previous=state>>8;state=((state<<1)|(((state>>15)^(state>>13)^(state>>12)^(state>>10))&1))&65535
        level=0 if level<=1024 else level-(level>>8)-1
        if level==0:break
    return (acc+noise)<<4,levels

def musicbox(o,k,length,new):
    t=np.arange(length,dtype=np.int64);acc=np.zeros(length,dtype=np.int64);levels=[]
    base=C4[k]>>(4-o) if o<=4 else C4[k]<<(o-4)
    main=BOX[((o-3)*12+k)*7]&0xffffff
    for m in range(32 if new else 7):
        if m<6 or not new:
            param=BOX[((o-3)*12+k)*7+m];amp=param&0xffffff;decay=param>>24
        else:
            amp=max(2048,round(main*(0.0032-0.0012*((m-6)/25))))
            decay=round(1800+2100*((m-6)/25))
        ratio=round(RATIOS[m]*4096) if new else OLD_RATIOS[m]
        step=((base>>8)*ratio)>>4
        seed=SEEDS[m] if m<7 else (0x9e3779b9*m)&0xffffffff
        phase=(seed+step*(t+1))&0xffffffff
        e=envelope(amp,decay,length,24,256,box=True)
        component=(BT[phase>>21]*(e>>8)+16384)>>15;acc+=component
        levels.append(float(np.sqrt(np.mean(component[:4883].astype(float)**2))))
    age=np.minimum(t,1023);attack=np.array([BOX[256+(128 if o>=5 else 0)+int(i>>3)]&65535 for i in age],dtype=np.int64)
    acc=(acc*attack+16384)>>15
    return acc<<4,levels

def wav(path,data):
    x=np.clip(np.rint(data),-8388608,8388607).astype(np.int32)
    packed=np.column_stack((x&255,(x>>8)&255,(x>>16)&255)).astype(np.uint8).tobytes()
    with wave.open(str(path),'wb') as f:f.setnchannels(1);f.setsampwidth(3);f.setframerate(round(FS));f.writeframes(packed)

def main():
    out=P/'audio';out.mkdir(exist_ok=True);stats=[];frames=round(FS*1.2);gap=np.zeros(round(FS*.15))
    for name,render in [('piano',piano),('musicbox',musicbox)]:
        sequence=[]
        for label,o,k in [('C3',3,0),('C4',4,0),('E4',4,4),('G4',4,7),('C5',5,0)]:
            a,la=render(o,k,frames,False);b,lb=render(o,k,frames,True)
            scale=.65*8388607/max(1,float(np.max(np.abs(a))))
            wav(out/f'51_{name}_{label}_old_MODEL.wav',a*scale)
            wav(out/f'51_{name}_{label}_new_MODEL.wav',b*scale)
            sequence.extend([a*scale,gap,b*scale,gap])
            stats.append({'instrument':name,'note':label,'waveform_relative_RMS_error':float(np.linalg.norm(b-a)/max(1,np.linalg.norm(a.astype(float)))),
                'level_delta_dB':float(20*np.log10(max(1,np.linalg.norm(b.astype(float)))/max(1,np.linalg.norm(a.astype(float))))),
                'first50ms_component_RMS':lb,'audition_type':'offline fixed-point modal model; not RTL or board recording','pair_gain':scale})
            print(name,label,'model rendered',flush=True)
        wav(out/f'51_{name}_five_notes_old_then_new_MODEL.wav',np.concatenate(sequence))
    (P/'verification/modal_audio_comparison_MODEL.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')

if __name__=='__main__':main()
