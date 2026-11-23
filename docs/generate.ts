// Writes one docs page per feature from src/<id>/devcontainer-feature.json into
// docs/content/features, plus an index with every feature. The docs site runs it before copying
// docs/content.
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"

type Option = { default?: string | boolean; description?: string; proposals?: string[]; enum?: string[] }
type Entry = { name: string; ports?: number[]; value?: string; target?: string; secret?: string; description?: string }
type Feature = {
  id: string
  version: string
  name: string
  description: string
  documentationURL: string
  options?: Record<string, Option>
  customizations?: { o3s?: { hosts?: Entry[]; env?: Entry[]; files?: Entry[] } }
}

const registry = "ghcr.io/hansehart/devcontainer-features"
const out = "docs/content/features"

// text in a table cell: MDX reads braces and angle brackets, tables split on pipes
const text = (s = "") => s.replace(/[{}|]/g, "\\$&").replace(/</g, "&lt;")
const code = (s: unknown) => `\`${String(s).replace(/\|/g, "\\|")}\``
const table = (head: string[], rows: string[][]) =>
  [`| ${head.join(" | ")} |`, `|${head.map(() => "---").join("|")}|`, ...rows.map((r) => `| ${r.join(" | ")} |`)].join("\n")

const features: Feature[] = readdirSync("src")
  .sort()
  .map((id) => JSON.parse(readFileSync(`src/${id}/devcontainer-feature.json`, "utf8")))

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })

for (const f of features) {
  const major = f.version.split(".")[0]
  const options = Object.entries(f.options ?? {})
  const o3s = f.customizations?.o3s ?? {}
  const page = [
    "---",
    `title: ${JSON.stringify(f.name)}`,
    `description: ${JSON.stringify(f.description)}`,
    "---",
    "",
    "## Usage",
    "",
    '```json title=".devcontainer/devcontainer.json"',
    JSON.stringify({ features: { [`${registry}/${f.id}:${major}`]: {} } }, null, 2),
    "```",
    "",
    `Version ${code(f.version)}, see the [changelog](${f.documentationURL}/CHANGELOG.md) for what changed.`,
  ]

  if (options.length) {
    page.push(
      "",
      "## Options",
      "",
      table(
        ["Option", "Default", "Description"],
        options.map(([name, o]) => [code(name), o.default === "" || o.default === undefined ? "" : code(o.default), text(o.description)]),
      ),
    )
  }

  page.push("", "## o3s", "")
  if (!o3s.hosts?.length && !o3s.env?.length && !o3s.files?.length) {
    page.push("This feature adds nothing to the o3s defaults.")
  }
  if (o3s.hosts?.length) {
    page.push(
      "The hosts the tool reaches:",
      "",
      table(
        ["Host", "Ports", "Secret", "For"],
        o3s.hosts.map((h) => [code(h.name), (h.ports ?? []).join(", "), h.secret ? code(h.secret) : "", text(h.description)]),
      ),
      "",
    )
  }
  if (o3s.env?.length) {
    page.push(
      "The variables that set its defaults:",
      "",
      table(["Variable", "Value", "For"], o3s.env.map((e) => [code(e.name), code(e.value), text(e.description)])),
      "",
    )
  }
  if (o3s.files?.length) {
    page.push(
      "The config files it reads:",
      "",
      table(["File", "Path", "For"], o3s.files.map((e) => [code(e.name), code(e.target), text(e.description)])),
      "",
    )
  }

  writeFileSync(`${out}/${f.id}.mdx`, `${page.join("\n").trimEnd()}\n`)
}

writeFileSync(
  `${out}/index.mdx`,
  [
    "---",
    "title: Features",
    "description: Every feature with its image and what it installs.",
    "---",
    "",
    table(
      ["Feature", "Description", "Image"],
      features.map((f) => [`[${text(f.name)}](/docs/devcontainer-features/features/${f.id})`, text(f.description), code(`${registry}/${f.id}`)]),
    ),
    "",
  ].join("\n"),
)

writeFileSync(`${out}/meta.json`, `${JSON.stringify({ title: "Features", pages: ["index", ...features.map((f) => f.id)] }, null, 2)}\n`)
