const rounds = [];
for (let round = 0; round < 2; round++) {
  rounds.push(await (async function () {
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
right.ontrack = event => {
  receivedTrack = true;
  receiverSource = audio.createMediaStreamSource(new MediaStream([event.track]));
  receiverSource.connect(analyser);
};
left.addTrack(output.stream.getAudioTracks()[0], output.stream);
left.addTransceiver('audio', {direction:'recvonly'});
left.addTransceiver('audio', {direction:'recvonly'});
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
    if (energy > 0.01 && inbound.some(s => s.packets > 10)) break;
  }
  return {ok:energy > 0.01 && receivedTrack && !candidateError, receivedTrack, energy, inbound, candidateError, states:[left.connectionState,right.connectionState], mids:left.getTransceivers().map(t => t.mid)};
} finally {
  oscillator.stop();
  output.stream.getTracks().forEach(track => track.stop());
  left.close();
  right.close();
  await audio.close();
}

  })());
}
return {ok:rounds.every(round=>round.ok),rounds};
