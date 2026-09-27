"""Check the retained CC0 source bytes, glTF dependencies and geometry budget."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
folder = root / "assets/environment/village-props-v1"
manifest = json.loads((folder / "sources.json").read_text())
models = {}
for name, record in manifest["files"].items():
    data = (folder / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == record["sha256"], name
    if not name.endswith(".gltf"):
        continue
    scene = json.loads(data)
    for dependency in scene.get("buffers", []) + scene.get("images", []):
        assert dependency["uri"] in manifest["files"], (name, dependency)
    assert len(scene["nodes"]) == 1 and "skin" not in scene["nodes"][0], name
    assert "rotation" not in scene["nodes"][0] and "scale" not in scene["nodes"][0], name
    positions = [scene["accessors"][part["attributes"]["POSITION"]]
                 for mesh in scene["meshes"] for part in mesh["primitives"]]
    minimum = [min(a["min"][i] for a in positions) for i in range(3)]
    maximum = [max(a["max"][i] for a in positions) for i in range(3)]
    triangles = sum(scene["accessors"][part["indices"]]["count"] // 3
                    for mesh in scene["meshes"] for part in mesh["primitives"])
    models[Path(name).stem] = {"triangles": triangles, "min_m": minimum,
                              "max_m": maximum,
                              "size_m": [maximum[i] - minimum[i] for i in range(3)]}
assert len(models) == 10
assert manifest["license"] == "CC0-1.0" and manifest["free_gltf_count"] == 94
assert max(m["triangles"] for m in models.values()) <= 4100
print(json.dumps({"source_sha_pass": len(manifest["files"]), "models": models}, indent=2))
