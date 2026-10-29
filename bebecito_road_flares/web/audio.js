'use strict';
// Audio-only NUI: no input handlers, cursor focus, external libraries or rendering loop.
class FlareMixer {
  constructor(factory, load, report, clock = globalThis) {
    this.factory=factory;this.load=load;this.report=report;this.clock=clock;
    this.voices=new Map();this.retiring=[];this.shots=new Set();this.playedShots=0;this.revision=0;this.timer=null;this.idle=null;this.buffer=null;this.retryAfter=0;this.disposed=false;
  }
  async prepare() {
    if (!this.context) this.context=this.factory();
    if (!this.loading) this.loading=this.load(this.context);
    this.buffer=await this.loading;
    if(this.context.state==='suspended')await this.context.resume();
  }
  drop(key, immediate=false) {
    const v=this.voices.get(key);if(!v)return;
    this.voices.delete(key);
    if(this.retiring.length>=4){const old=this.retiring.shift();old.source.stop();}
    this.retiring.push(v);
    const t=this.context.currentTime;
    v.gain.gain.cancelScheduledValues(t);
    v.gain.gain.setTargetAtTime(0,t,immediate?.001:.045);
    v.source.stop(t+(immediate?.005:.20));
    v.source.onended=()=>{this.retiring=this.retiring.filter(x=>x!==v);v.source.disconnect();v.gain.disconnect();v.pan.disconnect();};
  }
  async mix(input) {
    if(this.disposed)return;
    const revision=++this.revision;
    this.clock.clearTimeout(this.timer);this.clock.clearTimeout(this.idle);
    const sources=Array.isArray(input)?input.slice(0,4).filter(s=>s&&typeof s.id==='string'&&Number.isFinite(s.gain)&&Number.isFinite(s.pan)&&s.gain>0):[];
    if(!sources.length){
      for(const key of [...this.voices.keys()])this.drop(key);
      this.report({state:'idle',voices:0});
      this.idle=this.clock.setTimeout(()=>{if(this.revision===revision&&this.context)this.context.suspend().then(()=>{if(this.revision===revision)this.report({state:this.context.state,voices:0});}).catch(()=>{});},400);
      return;
    }
    if(Date.now()<this.retryAfter)return;
    try {
      await this.prepare();if(revision!==this.revision)return;
      const wanted=new Set(sources.map(s=>s.id));
      for(const key of this.voices.keys())if(!wanted.has(key))this.drop(key);
      const level=1/Math.sqrt(sources.length);
      for(const s of sources){
        let v=this.voices.get(s.id);
        if(!v){
          const source=this.context.createBufferSource(),gain=this.context.createGain(),pan=this.context.createStereoPanner();
          source.buffer=this.buffer;source.loop=true;
          gain.gain.value=0;source.connect(gain);gain.connect(pan);pan.connect(this.context.destination);
          let hash=0;for(const c of s.id)hash=(hash*31+c.charCodeAt(0))>>>0;
          source.playbackRate.value=.97+(hash%61)/1000;
          source.start(0,(hash%1000)/1000*this.buffer.duration);
          v={source,gain,pan};this.voices.set(s.id,v);
        }
        const t=this.context.currentTime;
        v.gain.gain.setTargetAtTime(Math.min(.5,Math.max(0,s.gain))*level,t,.06);
        v.pan.pan.setTargetAtTime(Math.max(-1,Math.min(1,s.pan)),t,.06);
      }
      this.report({state:this.context.state,voices:this.voices.size});
      this.timer=this.clock.setTimeout(()=>this.mix([]),1200);
    }catch(error){
      for(const key of [...this.voices.keys()])this.drop(key,true);
      this.report({state:'error',voices:0,error:String(error.message||error).slice(0,160)});
      this.loading=null;
      this.retryAfter=Date.now()+5000;
    }
  }
  async oneShot(name,gain,pan,load){
    if(!['strike','tap'].includes(name)||this.shots.size>=2)return;
    const requestedAt=Date.now();
    try{
      await this.prepare();const buffer=await load(this.context,name);
      if(this.disposed||Date.now()-requestedAt>500||this.shots.size>=2)return;
      const source=this.context.createBufferSource(),volume=this.context.createGain(),stereo=this.context.createStereoPanner();
      source.buffer=buffer;volume.gain.value=Math.min(.3,Math.max(0,Number(gain)||0));stereo.pan.value=Math.max(-1,Math.min(1,Number(pan)||0));
      source.connect(volume);volume.connect(stereo);stereo.connect(this.context.destination);this.shots.add(source);
      source.onended=()=>{this.shots.delete(source);source.disconnect();volume.disconnect();stereo.disconnect();};source.start();
      this.playedShots++;this.report({state:this.context.state,voices:this.voices.size});
      if(!this.voices.size){this.clock.clearTimeout(this.idle);this.idle=this.clock.setTimeout(()=>{if(!this.voices.size)this.context.suspend().catch(()=>{});},500);}
    }catch(error){this.report({state:'error',voices:this.voices.size,error:String(error.message||error).slice(0,160)});}
  }
  dispose(){this.disposed=true;this.revision++;this.clock.clearTimeout(this.timer);this.clock.clearTimeout(this.idle);for(const key of [...this.voices.keys()])this.drop(key,true);for(const v of this.retiring)v.source.stop();this.retiring=[];for(const s of this.shots)s.stop();this.shots.clear();if(this.context)this.context.close();}
}
if(typeof module!=='undefined')module.exports={FlareMixer};
if(typeof window!=='undefined'){
  let last='';
  const report=data=>{const value=JSON.stringify({...data,playedShots:mixer.playedShots});if(value===last)return;last=value;
    fetch(`https://${GetParentResourceName()}/bdAudioStatus`,{method:'POST',headers:{'Content-Type':'application/json'},body:value}).catch(()=>{});};
  const mixer=new FlareMixer(()=>new AudioContext(),async context=>{
    const response=await fetch('audio/combustion.wav');if(!response.ok)throw new Error('Audio asset unavailable');
    return context.decodeAudioData(await response.arrayBuffer());
  },report);
  const shotBuffers=new Map();
  const loadShot=(context,name)=>{if(!shotBuffers.has(name))shotBuffers.set(name,fetch(`audio/${name}.wav`).then(r=>{if(!r.ok)throw new Error('One-shot unavailable');return r.arrayBuffer();}).then(b=>context.decodeAudioData(b)));return shotBuffers.get(name);};
  window.addEventListener('message',event=>{
    if(event.data?.action==='bdFlareMix')void mixer.mix(event.data.sources);
    else if(event.data?.action==='bdFlareShot')void mixer.oneShot(event.data.name,event.data.gain,event.data.pan,loadShot);
  });
  window.addEventListener('pagehide',()=>mixer.dispose(),{once:true});
  report({state:'ready',voices:0});
}
