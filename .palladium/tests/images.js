const fixtures = {
  "PNG": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAE0lEQVR4nGMU2RLAAANMcBZeDgA3eAEgUl8l2QAAAABJRU5ErkJggg==",
  "JPEG": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAEAAQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCCiiivLPz8/9k=",
  "GIF": "data:image/gif;base64,R0lGODdhBAAEAIEAABS0UAAAAAAAAAAAACwAAAAABAAEAAAICQABCBxIsCCAgAA7",
  "WEBP": "data:image/webp;base64,UklGRjgAAABXRUJQVlA4ICwAAACQAQCdASoEAAQAAUAmJaACdLoAA5gA/tom/jfEF7V4/+1of+uz/9dn/PAAAA==",
  "AVIF": "data:image/avif;base64,AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUIAAADrbWV0YQAAAAAAAAAhaGRscgAAAAAAAAAAcGljdAAAAAAAAAAAAAAAAAAAAAAOcGl0bQAAAAAAAQAAAB5pbG9jAAAAAEQAAAEAAQAAAAEAAAETAAAAJwAAAChpaW5mAAAAAAABAAAAGmluZmUCAAAAAAEAAGF2MDFDb2xvcgAAAABqaXBycAAAAEtpcGNvAAAAFGlzcGUAAAAAAAAABAAAAAQAAAAQcGl4aQAAAAADCAgIAAAADGF2MUOBAAwAAAAAE2NvbHJuY2x4AAEADQAGgAAAABdpcG1hAAAAAAAAAAEAAQQBAoMEAAAAL21kYXQSAAoIGAR9ogIaDQgyGRTHh4ZlAgggnlAAAABIWtlc0s4LkEFml04="
};
const decoded=[];
for(const [format,url] of Object.entries(fixtures)) {
  const image=new Image();image.src=url;
  await image.decode();
  if(image.naturalWidth!==4 || image.naturalHeight!==4)throw new Error(format+' image dimensions are wrong');
  const canvas=document.createElement('canvas');canvas.width=4;canvas.height=4;
  const context=canvas.getContext('2d');context.drawImage(image,0,0);
  const pixel=context.getImageData(1,1,1,1).data;
  if(pixel[1]<140 || pixel[0]>65 || pixel[3]!==255)throw new Error(format+' image pixels were not decoded');
  decoded.push(format);
}
return {ok:decoded.length===5,decoded};
