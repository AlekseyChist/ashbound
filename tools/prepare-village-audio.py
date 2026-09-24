"""Rebuild game audio from preserved originals; requires numpy, imageio-ffmpeg.

No generation or downloading here. Sources and hashes live beside original audio.
"""
from pathlib import Path
import subprocess, hashlib, json
import numpy as np
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art/audio/village-v1'
DEST = ROOT / 'assets/audio'
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
RATE = 44100

def decode(path, channels):
    raw = subprocess.check_output([FFMPEG, '-v','error','-i',str(path),'-f','f32le','-ar',str(RATE),'-ac',str(channels),'-'])
    return np.frombuffer(raw, dtype='<f4').reshape(-1, channels).copy()

def process(record):
    src = SOURCE / record['file']
    assert hashlib.sha256(src.read_bytes()).hexdigest() == record['sha256'], src
    channels = 2 if record['kind'] == 'music' else 1
    data = decode(src, channels)
    original_seconds = len(data)/RATE
    if record['kind'] == 'loop':
        # Rotate an overlap of tail and head into the start: last retained sample
        # meets the first blend sample continuously. No repeated silence seam.
        overlap = min(int(.8*RATE),len(data)//5)
        weight = np.linspace(0,1,overlap,dtype=np.float32)[:,None]
        data = np.concatenate((data[-overlap:]*(1-weight)+data[:overlap]*weight,data[overlap:-overlap]))
    elif record['kind'] == 'music':
        fade = min(2*RATE,len(data)//10)
        data[:fade] *= np.linspace(0,1,fade)[:,None]
        data[-fade:] *= np.linspace(1,0,fade)[:,None]
    else:
        # Keep the recorded impact; only remove tiny DC/click edges.
        fade = min(220,len(data)//10)
        data[:fade] *= np.linspace(0,1,fade)[:,None]
        data[-fade:] *= np.linspace(1,0,fade)[:,None]
    data -= data.mean(axis=0)
    rms = float(np.sqrt(np.mean(data*data)))
    peak = float(np.max(np.abs(data)))
    target = .11 if record['kind']=='music' else .16
    gain = min(target/max(rms,1e-8),.82/max(peak,1e-8))
    data *= gain
    out = DEST / record['output']; out.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run([FFMPEG,'-v','error','-y','-f','f32le','-ar',str(RATE),'-ac',str(channels),'-i','-','-c:a','libvorbis','-q:a','4','-map_metadata','-1',str(out)],input=data.astype('<f4').tobytes(),check=True)
    actual = decode(out, channels)
    return {'file':out.relative_to(ROOT).as_posix(),'source_seconds':original_seconds,'seconds':len(actual)/RATE,'channels':channels,'gain_db':round(20*np.log10(gain),2),'peak':float(np.max(np.abs(actual))),'rms':float(np.sqrt(np.mean(actual*actual))),'loop_seam':float(np.max(np.abs(actual[0]-actual[-1]))),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}

if __name__ == '__main__':
    records = json.loads((SOURCE/'sources.json').read_text(encoding='utf-8'))['files']
    results = [process(record) for record in records]
    (DEST/'village-v1/analysis.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(f'AUDIO_PREPARED {len(results)} files, {sum((ROOT/r["file"]).stat().st_size for r in results)/1024**2:.2f} MiB')
