import { API_SURFACE_EXAMPLE } from "./analysisViewApiSurfaceExample.js";
import {
  analysisViewResultSchema,
  inspectAnalysisViewInputSchema,
} from "../domain/analysisView/analysisView.js";
import type { ToolContract } from "./toolContractTypes.js";
import { toolContractMetadata } from "./toolEffects.js";
import { evidenceResultOf } from "./toolOutputSchemaPrimitives.js";

const RETAINED_EXAMPLE_ID = `ev_${"a".repeat(64)}`;

/** Selected views of completed layout, JavaScript, native and inventory Evidence. */
export const ANALYSIS_VIEW_TOOL_CONTRACTS = [
  {
    name: "inspect_analysis_view",
    ...toolContractMetadata("inspect_analysis_view"),
    kind: "application",
    description:
      "Inspect selected views of completed binary-layout, JavaScript application, native analyze_function, inspect_artifact or inventory_artifact Evidence without repeating analysis. The api-surface view groups retained HAR requests by method, origin and format-rule path template; templated segments are inferences. It reads no headers or bodies and reports no query values. Use an exact same-session retained evidence_id or portable inline Evidence. Select a summary, layout mitigations/linkage facet, one section/symbol/module, or a stable page. Module pages include assets, bundled and source modules; use node_id for ambiguous or unavailable paths. Inventory views page nodes, occurrences, edges or integrity contradictions; occurrence logical_paths matches exact recorded strings (omitted means all available, [] means none). source_complete distinguishes complete inventories from partial source records; page exhaustion does not prove absence in a partial source. Native views select procedure, pseudocode, assembly, basic blocks, comments, callers/callees, references, unresolved calls, referenced strings/names, native API and high-pcode. Use nonnegative offset and a positive caller-selected limit (defaults 0 and 64); pseudocode uses UTF-16 code units, other native pages use rows. Returns artifact identity, parent Evidence ID, a distinct view digest, coverage, limitations and unknowns. Actual serialized size determines MCP transport admission; choose a smaller page or export the complete retained Evidence if needed.",
    inputSchema: inspectAnalysisViewInputSchema,
    outputSchema: evidenceResultOf(analysisViewResultSchema),
    examples: [
      {
        title: "Group requests from retained HAR Evidence",
        input: API_SURFACE_EXAMPLE.input,
      },
      {
        title: "Read exact inventory paths from retained inspection Evidence",
        input: {
          source: {
            kind: "retained-evidence",
            evidence_id: RETAINED_EXAMPLE_ID,
          },
          view: {
            kind: "inventory",
            collection: "occurrences",
            logical_paths: ["package.json", "main.js"],
            offset: 0,
            limit: 32,
          },
        },
      },
      {
        title: "Summarize retained JavaScript application Evidence",
        input: {
          source: {
            kind: "retained-evidence",
            evidence_id: RETAINED_EXAMPLE_ID,
          },
          view: { kind: "summary" },
        },
      },
      {
        title: "Read one ELF section from retained layout Evidence",
        input: {
          source: {
            kind: "retained-evidence",
            evidence_id: RETAINED_EXAMPLE_ID,
          },
          view: {
            kind: "item",
            collection: "sections",
            selector: { name: ".text" },
          },
        },
      },
      {
        title: "Page native high-pcode operations from retained Evidence",
        input: {
          source: {
            kind: "retained-evidence",
            evidence_id: RETAINED_EXAMPLE_ID,
          },
          view: {
            kind: "native",
            facet: "value_flow_operations",
            offset: 0,
            limit: 32,
          },
        },
      },
      {
        title: "Page module identities from retained application Evidence",
        input: {
          source: {
            kind: "retained-evidence",
            evidence_id: RETAINED_EXAMPLE_ID,
          },
          view: {
            kind: "page",
            collection: "modules",
            offset: 0,
            limit: 32,
          },
        },
      },
    ],
  },
] as const satisfies readonly ToolContract[];
