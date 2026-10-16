const context = new AudioContext();
const oscillator = context.createOscillator();
const destination = context.createMediaStreamDestination();
const element = new Audio();
let microphone;
let toneStarted=false;
let changes = 0;
navigator.mediaDevices.addEventListener('devicechange', () => changes++);
async function wait(predicate, message) {
  for(let iteration=0;iteration<60;iteration++) {
    if(await predicate())return;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  throw new Error(message);
}
async function outputs() {
  return (await navigator.mediaDevices.enumerateDevices()).filter(device=>device.kind==='audiooutput');
}
async function control(operation) {
  document.title='WEBKIT_CONTROL:'+operation;
  await wait(()=>window.__PALLADIUM_DEVICE_CONTROL__===operation,'device control timed out');
}
try {
  document.title="WEBKIT_PROGRESS:capture";
  microphone=await navigator.mediaDevices.getUserMedia({audio:true});
  const input=microphone.getAudioTracks()[0];
  if(input.readyState!=='live')throw new Error('microphone capture did not start');
  document.title="WEBKIT_PROGRESS:enumerate";
  const initial=await outputs();
  if(initial.length<2)throw new Error('two isolated output devices are required');
  if(typeof element.setSinkId!=='function')throw new Error('output selection unavailable');
  const firstOutput=initial.find(device=>device.deviceId!=='default' && device.label.includes('Palladium_Test_First'));
  const secondOutput=initial.find(device=>device.deviceId!=='default' && device.label.includes('Palladium_Test_Second'));
  if(!firstOutput || !secondOutput)throw new Error('isolated output labels are missing');
  oscillator.connect(destination);oscillator.start();toneStarted=true;await context.resume();
  element.srcObject=destination.stream;
  document.title="WEBKIT_PROGRESS:output-switch";
  await element.setSinkId(firstOutput.deviceId);
  await element.play();
  await element.setSinkId(secondOutput.deviceId);
  if(element.sinkId!==secondOutput.deviceId)throw new Error('output selection did not change');
  await control('measure-output');
  const outputEnergy=window.__PALLADIUM_OUTPUT_ENERGY__ || 0;
  if(outputEnergy<0.01)throw new Error('selected virtual speaker has no tone');
  let before=changes;
  await control('add');
  await wait(async()=>changes>before && (await outputs()).length>initial.length,'new output was not reported');
  before=changes;
  await control('default');
  await wait(()=>changes>before,'default output change did not notify the page');
  before=changes;
  await control('remove');
  await wait(async()=>changes>before && (await outputs()).length===initial.length,'removed output remained in the device list');
  const final=await outputs();
  return {ok:input.readyState==='live' && final.length===initial.length,changes,initialOutputs:initial.length,finalOutputs:final.length,capture:input.readyState,outputSwitched:true,outputEnergy};
} finally {
  if(microphone)microphone.getTracks().forEach(track=>track.stop());
  destination.stream.getTracks().forEach(track=>track.stop());
  element.pause();element.srcObject=null;if(toneStarted)oscillator.stop();await context.close();
}
