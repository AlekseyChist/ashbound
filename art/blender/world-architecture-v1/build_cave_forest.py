"""The Forest cave's interior (WORLD-PLAN-01, CAVE-01): build_cave.py with forest_cave - one recipe for
every cave (Codex 305/330/343). Usage: blender -b --python build_cave_forest.py"""
import runpy,sys
from pathlib import Path
sys.argv=[sys.argv[0],'--','forest_cave']
runpy.run_path(str(Path(__file__).with_name('build_cave.py')),run_name='__main__')
