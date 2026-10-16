const incoming = new RTCPeerConnection();
const outgoing = new RTCPeerConnection();
const context = new AudioContext();
const oscillator = context.createOscillator();
const destination = context.createMediaStreamDestination();
const analyser = context.createAnalyser();
oscillator.connect(destination);
oscillator.start();
await context.resume();
const toIncoming = [];
const toOutgoing = [];
let errors = [];
let source;
let secondSource;
const secondAnalyser = context.createAnalyser();
let forwarded = 0;
let dropped = 0;
let secondEnergy = 0;
let events = 0;
incoming.onicecandidate = event => {
  if (!event.candidate) return;
  if (outgoing.remoteDescription) outgoing.addIceCandidate(event.candidate).catch(e => errors.push(e.name));
  else toOutgoing.push(event.candidate);
};
outgoing.onicecandidate = event => {
  if (!event.candidate) return;
  if (incoming.remoteDescription) incoming.addIceCandidate(event.candidate).catch(e => errors.push(e.name));
  else toIncoming.push(event.candidate);
};
incoming.ontrack = event => {
  events++;
  if (event.receiver === first.receiver) {
    source = context.createMediaStreamSource(new MediaStream([event.track]));
    source.connect(analyser);
  } else {
    secondSource = context.createMediaStreamSource(new MediaStream([event.track]));
    secondSource.connect(secondAnalyser);
  }
};
const first = incoming.addTransceiver('audio', {direction:'recvonly'});
incoming.addTransceiver('audio', {direction:'recvonly'});
const workerSource='self.allow=false;let count=0;self.onmessage=e=>self.allow=e.data;self.onrtctransform=e=>e.transformer.readable.pipeThrough(new TransformStream({transform(frame,controller){if(self.allow)controller.enqueue(frame);if(++count%10===0)self.postMessage({allow:self.allow,count})}})).pipeTo(e.transformer.writable).catch(e=>self.postMessage({error:e.name}));';
const workers=[];
for (let index=0;index<2;index++) {
 const track=destination.stream.getAudioTracks()[0].clone();
 const stream=new MediaStream([track]);
 const transceiver=outgoing.addTransceiver(track,{direction:'sendonly',streams:[index===0?destination.stream:stream]});
 const worker=new Worker(URL.createObjectURL(new Blob([workerSource],{type:'text/javascript'})));
 worker.onmessage=e=>{if(e.data.error)errors.push(e.data.error);else if(index===0 && e.data.allow)forwarded=e.data.count;else if(index===1 && !e.data.allow)dropped=e.data.count};
 transceiver.sender.transform=new RTCRtpScriptTransform(worker);
 workers.push(worker);
}

try {
  const offer = await incoming.createOffer();
  await incoming.setLocalDescription(offer);
  await outgoing.setRemoteDescription(offer);
  for (const candidate of toOutgoing.splice(0)) await outgoing.addIceCandidate(candidate);
  const answer = await outgoing.createAnswer();
  await outgoing.setLocalDescription(answer);
  await incoming.setRemoteDescription(answer);
  for (const candidate of toIncoming.splice(0)) await incoming.addIceCandidate(candidate);
  await new Promise(resolve=>setTimeout(resolve,200));
  workers[0].postMessage(true);
  let energy = 0;
  let received = 0;
  for (let iteration=0;iteration<50;iteration++) {
    await new Promise(resolve=>setTimeout(resolve,100));
    const samples=new Float32Array(analyser.fftSize);
    analyser.getFloatTimeDomainData(samples);
    energy=samples.reduce((sum,sample)=>sum+sample*sample,0)/samples.length;
    (await incoming.getStats()).forEach(value=>{if(value.type==='inbound-rtp')received=Math.max(received,value.packetsReceived||0)});
    if(energy>0.01 && received>10 && forwarded>=10 && dropped>=10)break;
  }
  const firstPassed = energy>0.01 && received>10 && forwarded>=10 && dropped>=10;
  workers[1].postMessage(true);
  for(let iteration=0;iteration<30;iteration++){
    await new Promise(resolve=>setTimeout(resolve,100));
    const samples=new Float32Array(secondAnalyser.fftSize);
    secondAnalyser.getFloatTimeDomainData(samples);
    secondEnergy=samples.reduce((sum,sample)=>sum+sample*sample,0)/samples.length;
    if(secondEnergy>0.01)break;
  }
  return {ok:firstPassed && secondEnergy>0.01 && !errors.length,energy,secondEnergy,forwarded,dropped,received,events,errors,tracks:incoming.getTransceivers().map(t=>({direction:t.currentDirection,muted:t.receiver.track.muted}))};
} finally {
  workers.forEach(w=>w.terminate());incoming.close();outgoing.close();oscillator.stop();destination.stream.getTracks().forEach(t=>t.stop());await context.close();
}
