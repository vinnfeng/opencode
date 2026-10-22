import { expect, test } from "bun:test"
import { Effect } from "effect"
import { mkdir } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"
import { cliIt } from "../lib/cli-process"
import { reply } from "../lib/llm-server"
import { testProviderConfig } from "../lib/test-provider"

// An opt-in regression against an explicitly supplied local plugin. Use a
// clean environment and restrict network access to the synthetic LLM server.
const plugin = process.env.OPENCODE_SYNTHETIC_PLUGIN_URI || ""

if (!plugin) {
  test.skip("plugin hooks preserve synthetic tool continuation", () => {})
} else {
  if (!plugin.startsWith("file://")) throw new Error("synthetic plugin must be a local file URI")
  cliIt.live("plugin hooks preserve synthetic tool continuation", ({ home, llm, opencode }) =>
    Effect.gen(function* () {
      const wrapper = path.join(home, "plugin-observed.mjs")
      const marker = path.join(home, "plugin-event.txt")
      const configDir = path.join(home, ".config", "opencode")
      yield* Effect.promise(() => mkdir(path.join(configDir, "node_modules"), { recursive: true }))
      yield* Effect.promise(() => Bun.write(path.join(configDir, "package-lock.json"), JSON.stringify({
        packages: { "": { dependencies: { "@opencode-ai/plugin": "*" } } },
      })))
      yield* Effect.promise(() => Bun.write(wrapper, `
        import actual from ${JSON.stringify(plugin)};
        export default {
          id: 'synthetic-observed-plugin',
          server: async (...args) => {
            const hooks = await actual.server(...args);
            return { ...hooks, event: async (...eventArgs) => {
              await Bun.write(${JSON.stringify(marker)}, 'event');
              return hooks.event?.(...eventArgs);
            }};
          },
        };
      `))
      yield* llm.push(reply().text("before").tool("bash", {
        command: "printf tool-output", description: "Print deterministic output",
      }))
      yield* llm.text("after")
      const result = yield* opencode.run("use a tool", {
        format: "json", extraArgs: ["--dangerously-skip-permissions"],
        env: {
          OPENCODE_PURE: "false", OPENCODE_DISABLE_DEFAULT_PLUGINS: "true",
          OPENCODE_CONFIG_CONTENT: JSON.stringify({ ...testProviderConfig(llm.url), plugin: [pathToFileURL(wrapper).href] }),
        },
      })
      opencode.expectExit(result, 0)
      const events = opencode.parseJsonEvents(result.stdout)
      expect(events.some((event) => event.type === "tool_use")).toBe(true)
      expect(events.some((event) => event.type === "text" && JSON.stringify(event).includes("after"))).toBe(true)
      expect(yield* Effect.promise(() => Bun.file(marker).exists())).toBe(true)
    }),
    90_000,
  )
}
