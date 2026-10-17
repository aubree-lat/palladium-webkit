const left = new RTCPeerConnection();
const right = new RTCPeerConnection();
const audio = new AudioContext();
const oscillator = audio.createOscillator();
const output = audio.createMediaStreamDestination();
const analyser = audio.createAnalyser();
oscillator.connect(output);
oscillator.start();
await audio.resume();
let receivedTrack = false;
let receiverSource;
let candidateError = null;
const leftQueue = [];
const rightQueue = [];
function route(candidate, destination, queue) {
  if (!candidate) return;
  if (destination.remoteDescription) destination.addIceCandidate(candidate).catch(e => candidateError = e.name);
  else queue.push(candidate);
}
left.onicecandidate = event => route(event.candidate, right, rightQueue);
right.onicecandidate = event => route(event.candidate, left, leftQueue);
const workers = [];
const counts = { encrypt: 0, decrypt: 0 };
const failures = [];
const epochs = {encrypt:1,decrypt:1};
let replacements = 0;
let detachedAudioWorks = false;
const workerText = `self.pause=false;self.onmessage=event=>self.pause=Boolean(event.data);self.onrtctransform = async event => {
  const { readable, writable, options } = event.transformer;
  let count = 0;
  let sequence = 0;
  try {
    // Fixed key for this synthetic CI test only. No Discord keys are used.
    const key = await crypto.subtle.importKey('raw', new Uint8Array(32).fill(41), 'AES-GCM', false, ['encrypt', 'decrypt']);
    await readable.pipeThrough(new TransformStream({async transform(frame, controller) {
      if(self.pause)return;
      if (frame.constructor.name !== 'RTCEncodedAudioFrame') throw new Error('incorrect frame type');
      const metadata = frame.getMetadata();
      if (metadata.synchronizationSource === undefined || metadata.rtpTimestamp === undefined) throw new Error('missing RTP metadata');
      if (options.operation === 'encrypt') {
        const iv = new Uint8Array(12);
        new DataView(iv.buffer).setUint32(0, options.epoch);
        new DataView(iv.buffer).setUint32(8, ++sequence);
        const cipher = new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv}, key, frame.data));
        const wire = new Uint8Array(iv.length + cipher.length);
        wire.set(iv); wire.set(cipher, iv.length); frame.data = wire.buffer;
      } else {
        const wire = new Uint8Array(frame.data);
        frame.data = await crypto.subtle.decrypt({name:'AES-GCM',iv:wire.slice(0,12)}, key, wire.slice(12));
      }
      controller.enqueue(frame);
      if (++count % 10 === 0) self.postMessage({operation:options.operation,epoch:options.epoch,count});
    }})).pipeTo(writable);
  } catch (e) { self.postMessage({operation:options.operation,epoch:options.epoch,error:e.name+': '+e.message}); }
};`;
const workerUrl = URL.createObjectURL(new Blob([workerText], {type:'text/javascript'}));
function transform(endpoint, operation, epoch=1) {
  epochs[operation]=epoch;
  const worker = new Worker(workerUrl);
  worker.onmessage = event => {
    if (event.data.error && epochs[event.data.operation]===event.data.epoch) failures.push(event.data.error);
    else if(epochs[event.data.operation]===event.data.epoch)counts[event.data.operation] = event.data.count;
  };
  workers.push(worker);
  endpoint.transform = new RTCRtpScriptTransform(worker, {operation,epoch});
  return worker;
}
right.ontrack = event => {
  transform(event.receiver, 'decrypt');
  receivedTrack = true;
  receiverSource = audio.createMediaStreamSource(new MediaStream([event.track]));
  receiverSource.connect(analyser);
};
const sender = left.addTransceiver("audio", {direction:"sendonly"}).sender;


let currentSenderWorker=transform(sender, 'encrypt');
await sender.replaceTrack(output.stream.getAudioTracks()[0]);
try {
  for (let iteration = 0; iteration < 2; iteration++) {
    const offer = await left.createOffer();
    await left.setLocalDescription(offer);
    await right.setRemoteDescription(offer);
    for (const candidate of rightQueue.splice(0)) await right.addIceCandidate(candidate);
    const answer = await right.createAnswer();
    await right.setLocalDescription(answer);
    await left.setRemoteDescription(answer);
    for (const candidate of leftQueue.splice(0)) await left.addIceCandidate(candidate);
  }
  let energy = 0;
  let inbound = [];
  for (let attempt = 0; attempt < 40; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 150));
    const samples = new Float32Array(analyser.fftSize);
    analyser.getFloatTimeDomainData(samples);
    energy = samples.reduce((sum, sample) => sum + sample * sample, 0) / samples.length;
    inbound = Array.from((await right.getStats()).values()).filter(s => s.type === 'inbound-rtp').map(s => ({kind:s.kind, bytes:s.bytesReceived, packets:s.packetsReceived}));
    if (energy > 0.01 && counts.encrypt >= 10 && counts.decrypt >= 10) break;
  }
  const initialPassed = energy>0.01 && counts.encrypt>=10 && counts.decrypt>=10;
  if(initialPassed) {
    for(let epoch=2;epoch<=4;epoch++) {
      counts.encrypt=0;counts.decrypt=0;
      currentSenderWorker=transform(sender,'encrypt',epoch);
      right.getReceivers().forEach(receiver=>transform(receiver,'decrypt',epoch));
      let recovered=false;
      for(let iteration=0;iteration<30;iteration++) {
        await new Promise(resolve=>setTimeout(resolve,100));
        const samples=new Float32Array(analyser.fftSize);analyser.getFloatTimeDomainData(samples);
        energy=samples.reduce((sum,sample)=>sum+sample*sample,0)/samples.length;
        if(energy>0.01 && counts.encrypt>=10 && counts.decrypt>=10){recovered=true;break;}
      }
      if(!recovered)break;
      replacements++;
    }
    currentSenderWorker.postMessage(true);
    await new Promise(resolve=>setTimeout(resolve,600));
    epochs.encrypt++;epochs.decrypt++;
    right.getReceivers().forEach(receiver=>receiver.transform=null);
    sender.transform=null;
    await new Promise(resolve=>setTimeout(resolve,800));
    const samples=new Float32Array(analyser.fftSize);analyser.getFloatTimeDomainData(samples);
    energy=samples.reduce((sum,sample)=>sum+sample*sample,0)/samples.length;
    detachedAudioWorks=energy>0.01;
  }
  return {ok:initialPassed && replacements===3 && detachedAudioWorks && receivedTrack && !candidateError && !failures.length, counts, failures, replacements, detachedAudioWorks, receivedTrack, energy, inbound, candidateError, states:[left.connectionState,right.connectionState], mids:left.getTransceivers().map(t => t.mid)};
} finally {
  workers.forEach(worker => worker.terminate());
  URL.revokeObjectURL(workerUrl);
  oscillator.stop();
  output.stream.getTracks().forEach(track => track.stop());
  left.close();
  right.close();
  await audio.close();
}
