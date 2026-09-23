// Build-only experiment. Never write preview values into the source game's resources.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
const digest=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');

export function stageWalkPhonePreview(root,stage){
 const relative=path.relative(root,stage);
 if(!relative.startsWith(`.tools${path.sep}export-staging${path.sep}`))throw Error('Preview must stay inside export staging.');
 const source='art/characters/walk-consistency-v1/walk-atlas.png';
 const asset='assets/characters/courtyard/walk-phone-preview/walk.png';
 const resource='assets/characters/courtyard/traveler_frames.tres';
 const run='assets/characters/courtyard/painted-motion-v2/run.png';
 fs.mkdirSync(path.dirname(path.join(stage,asset)),{recursive:true});
 fs.copyFileSync(path.join(root,source),path.join(stage,asset));
 let text=fs.readFileSync(path.join(root,resource),'utf8').replaceAll('\r\n','\n');
 const old='res://assets/characters/courtyard/painted-motion-v2/walk.png';
 if(text.split(old).length!==2)throw Error('Walking source contract changed.');
 text=text.replace(old,'res://'+asset);
 const values={};
 for(const key of ['side','back','front','run_back','run_front','run_side']){
  const match=text.match(new RegExp(`^metadata/pixel_size_${key} = ([0-9.]+)$`,'m'));
  if(!match)throw Error('Missing scale '+key);
  values[key]=Number(match[1]);
 }
 if(text.includes('metadata/pixel_size_walk_side'))throw Error('Walk scale already present; review preview contract.');
 const scales={walk_side:values.side*.95,run_side:values.run_side*.9,run_front:values.run_front/.9,run_back:values.run_back/.9};
 for(const[key,value]of Object.entries(scales)){
  if(key==='walk_side')text+=`\nmetadata/pixel_size_${key} = ${value}\n`;
  else text=text.replace(new RegExp(`^metadata/pixel_size_${key} = [0-9.]+$`,'m'),`metadata/pixel_size_${key} = ${value}`);
 }
 fs.writeFileSync(path.join(stage,resource),text);
 for(const ext of ['gd','tscn']){
  fs.copyFileSync(path.join(root,`tools/qa/validate_walk_phone.${ext}`),path.join(stage,`scripts/tools/validate_walk_phone.${ext}`));
 }
 return {source,sourceSHA256:digest(path.join(root,source)),asset,resource,resourceSHA256:digest(path.join(stage,resource)),runSHA256:digest(path.join(stage,run)),scales};
}
