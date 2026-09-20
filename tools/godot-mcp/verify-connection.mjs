import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport, getDefaultEnvironment } from '@modelcontextprotocol/sdk/client/stdio.js';

const serverPath = fileURLToPath(new URL('./node_modules/@coding-solo/godot-mcp/build/index.js', import.meta.url));
const godotPath = fileURLToPath(new URL('../godot/Godot_v4.7.2-stable_win64.exe', import.meta.url));
const client = new Client({ name: 'ashbound-connection-check', version: '1.0.0' }, { capabilities: {} });
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [serverPath],
  env: { ...getDefaultEnvironment(), GODOT_PATH: godotPath },
});
const deadline = setTimeout(() => {
  console.error('Godot MCP connection check timed out.');
  process.exit(1);
}, 20000);

try {
  await client.connect(transport);
  const { tools } = await client.listTools();
  const version = await client.callTool({ name: 'get_godot_version', arguments: {} });
  if (version.isError) throw new Error(JSON.stringify(version));
  const versionText = version.content.filter(item => item.type === 'text').map(item => item.text).join('\n');
  if (!versionText.includes('4.7.2')) throw new Error(`Unexpected Godot response: ${versionText}`);
  console.log(JSON.stringify({ server: client.getServerVersion(), godot: versionText, toolCount: tools.length, tools: tools.map(tool => tool.name) }, null, 2));
  if (process.argv[2]) {
    const project = await client.callTool({ name: 'get_project_info', arguments: { projectPath: process.argv[2] } });
    if (project.isError) throw new Error(JSON.stringify(project));
    console.log(JSON.stringify({ project }, null, 2));
  }
} finally {
  clearTimeout(deadline);
  await client.close();
}
