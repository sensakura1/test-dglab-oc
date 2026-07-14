import { RealCoyoteAdapter } from "../src/core/device/realCoyoteAdapter.js";

const [command, rawConfig, rawActivation] = process.argv.slice(2);

function print(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

async function main() {
  if (!command || !rawConfig) {
    print({ ok: false, error: "Usage: node scripts/device-bridge.js <connect|activate|stop> <config-json> [activation-json]" });
    process.exitCode = 2;
    return;
  }

  const config = JSON.parse(rawConfig);
  const adapter = new RealCoyoteAdapter(config);

  try {
    await adapter.connect();
    if (command === "activate") {
      const activation = rawActivation ? JSON.parse(rawActivation) : {
        intensity: 10,
        durationMs: 1000,
        channel: config.channel ?? "both",
        pattern: config.pattern ?? "constant"
      };
      await adapter.activate(activation);
      print({ ok: true, command, activation });
    } else if (command === "stop") {
      await adapter.stop();
      print({ ok: true, command });
    } else if (command === "connect") {
      print({ ok: true, command, status: await adapter.getStatus() });
    } else {
      throw new Error(`Unknown command: ${command}`);
    }
    await adapter.disconnect();
  } catch (error) {
    print({ ok: false, command, error: error.message });
    process.exitCode = 1;
  }
}

await main();
