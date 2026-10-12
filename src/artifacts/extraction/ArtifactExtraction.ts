import { lstat, realpath } from "node:fs/promises";

import { compareUnicodeCodePoints } from "../../domain/unicodeCodePointOrder.js";
import { digestCanonicalValue } from "../../domain/canonicalDigest.js";
import { AsarArtifactReader } from "../AsarArtifactReader.js";
import { XarArtifactReader } from "../XarArtifactReader.js";
import { ArtifactPathRegistry } from "../ArtifactPaths.js";
import { visitArtifactTree } from "../ArtifactTraversal.js";
import {
  ArtifactReaderFailure,
  type ArtifactEntry,
  type ArtifactReader,
} from "../ArtifactReader.js";
import { abortIfNeeded } from "../ArtifactHash.js";
import { DirectoryArtifactReader } from "../DirectoryArtifactReader.js";
import { SafeOutputTree } from "../SafeOutputTree.js";
import { SafeOutputTreeCreationFailure } from "../SafeOutputTreeCreationFailure.js";
import { ZipArtifactReader } from "../ZipArtifactReader.js";
import { MachOSliceArtifactReader } from "../MachOSliceArtifactReader.js";
import {
  artifactExtractionResultSchema,
  type ArtifactExtractionResult,
  type ArtifactGraphManifest,
  type ArtifactNode,
  type ArtifactOccurrence,
  type IntegrityContradiction,
} from "../../domain/artifactGraph.js";
import { AnalysisUnsupportedTargetError } from "../../domain/analysisErrorCore.js";
import type {
  ArtifactResourceOwner,
  ArtifactResourceScope,
} from "../ArtifactResourceScope.js";
import {
  isMachOFormat,
  type BinaryTarget,
} from "../../domain/binaryTargetTypes.js";
import type { ArtifactInventorySnapshot } from "../../domain/artifactInventorySnapshot.js";
import { scanArtifactInventoryInScope } from "../inventory/ArtifactInventory.js";
import type { ArtifactIntegrityPolicyName } from "../../domain/artifactIntegrityPolicy.js";

/** Local extraction input with the output root chosen by the adapter. */
export interface ArtifactExtractionInput {
  readonly inputPath: string;
  readonly inputFormat: BinaryTarget["format"];
  readonly outputRoot: string;
  readonly environment: Readonly<NodeJS.ProcessEnv>;
  readonly integrityPolicy: ArtifactIntegrityPolicyName;
  readonly resourceScope: ArtifactResourceScope;
}

/** Extract every regular inventory occurrence into an exclusively owned absent root. */
export const extractArtifact = async (
  input: ArtifactExtractionInput,
  signal?: AbortSignal,
): Promise<ArtifactExtractionResult> =>
  input.resourceScope.run(() => extractArtifactInScope(input, signal));

const extractArtifactInScope = async (
  input: ArtifactExtractionInput,
  signal?: AbortSignal,
): Promise<ArtifactExtractionResult> => {
  // Cancellation wins over every later refusal, including unsupported formats.
  abortIfNeeded(signal);
  const sourcePath = await realpath(input.inputPath);
  await requireExtractableFormat(sourcePath, input);
  const snapshot = await scanArtifactInventoryInScope(sourcePath, {
    resourceScope: input.resourceScope,
    signal,
    environment: input.environment,
    integrity: { mode: input.integrityPolicy },
  });
  return materializeArtifactInventoryInScope(
    input,
    sourcePath,
    snapshot,
    signal,
  );
};

/** Materialize a scanned inventory, verifying every current occurrence against it. */
export const materializeArtifactInventory = async (
  input: ArtifactExtractionInput,
  sourcePath: string,
  snapshot: ArtifactInventorySnapshot,
  signal?: AbortSignal,
): Promise<ArtifactExtractionResult> => {
  return input.resourceScope.run(() =>
    materializeArtifactInventoryInScope(input, sourcePath, snapshot, signal),
  );
};

const materializeArtifactInventoryInScope = async (
  input: ArtifactExtractionInput,
  sourcePath: string,
  snapshot: ArtifactInventorySnapshot,
  signal?: AbortSignal,
): Promise<ArtifactExtractionResult> => {
  abortIfNeeded(signal);
  const byId = new Map(
    snapshot.occurrences.map((occurrence) => [
      occurrence.occurrence_id,
      occurrence,
    ]),
  );
  // A file/slice occurrence that owns child occurrences was expanded as a
  // container during the scan. Extraction re-expands the same gzip-cpio
  // members but keeps ASAR members opaque as regular files.
  const expandedContainerIds = new Set(
    snapshot.occurrences
      .map(({ parent_occurrence_id: id }) => id)
      .filter((id): id is string => id !== null),
  );
  const reexpandsInExtraction = (occurrence: ArtifactOccurrence): boolean =>
    expandedContainerIds.has(occurrence.occurrence_id) &&
    occurrence.artifact_format !== "asar";
  const insideOpaqueFile = (occurrence: ArtifactOccurrence): boolean => {
    // Members nested under a container the reader will not expand remain
    // represented by their containing regular file.
    let parent =
      occurrence.parent_occurrence_id === null
        ? undefined
        : byId.get(occurrence.parent_occurrence_id);
    while (parent !== undefined) {
      if (parent.entry_kind === "file" || parent.entry_kind === "slice")
        return !reexpandsInExtraction(parent);
      parent =
        parent.parent_occurrence_id === null
          ? undefined
          : byId.get(parent.parent_occurrence_id);
    }
    return false;
  };
  const activeOccurrences = snapshot.occurrences.filter(
    (occurrence) =>
      (occurrence.entry_kind === "file" || occurrence.entry_kind === "slice") &&
      occurrence.hash_status !== "unavailable" &&
      occurrence.logical_path !== "." &&
      // Re-expanded containers materialize their children, not their own bytes.
      !reexpandsInExtraction(occurrence) &&
      !insideOpaqueFile(occurrence),
  );
  const selectedIds = new Set(
    activeOccurrences.map(({ occurrence_id: id }) => id),
  );
  const neededNodes = new Set(
    activeOccurrences.map(({ artifact_id: id }) => id),
  );
  const nodes = new Map<string, ArtifactNode>();
  for (const node of snapshot.nodes)
    if (neededNodes.has(node.artifact_id)) nodes.set(node.artifact_id, node);
  const inventory: ExtractionInventory = {
    manifest: snapshot.manifest,
    integrityContradictions: snapshot.integrity_contradictions.filter(
      ({ occurrence_id: id }) => selectedIds.has(id),
    ),
    unavailablePaths: new Set(
      snapshot.occurrences
        .filter(({ hash_status }) => hash_status === "unavailable")
        .map(({ logical_path }) => logical_path),
    ),
  };
  const selected = activeOccurrences.map((occurrence) => {
    // REA never decrypts archive entries, so an encrypted entry makes the
    // complete extraction unsupported rather than the archive invalid.
    if (occurrence.encrypted)
      throw new AnalysisUnsupportedTargetError(
        "extract_artifact",
        input.inputPath,
        `Archive entry ${occurrence.logical_path} is encrypted; REA does not decrypt archive entries, so the archive cannot be extracted completely`,
      );
    // Inventory keeps an ASAR unpacked entry whose companion file is absent,
    // but extraction cannot materialize bytes it never observed.
    if (
      occurrence.entry_kind === "file" &&
      occurrence.artifact_id === null &&
      occurrence.hash_status === "unavailable"
    )
      throw new ArtifactReaderFailure(
        "unavailable",
        `ASAR unpacked companion bytes are unavailable for ${occurrence.logical_path}`,
        undefined,
        {
          logicalPath: occurrence.logical_path,
          declaredSha256: null,
          calculatedSha256: null,
          unpacked: true,
        },
      );
    if (
      (occurrence.entry_kind !== "file" && occurrence.entry_kind !== "slice") ||
      occurrence.artifact_id === null ||
      occurrence.logical_path === "."
    )
      throw new ArtifactReaderFailure(
        "format",
        `Selected occurrence is not an extractable regular child file: ${occurrence.logical_path} (${occurrence.occurrence_id})`,
      );
    const node = nodes.get(occurrence.artifact_id);
    if (node === undefined)
      throw new ArtifactReaderFailure(
        "integrity",
        `Selected occurrence has no inventory node: ${occurrence.occurrence_id}`,
      );
    return { occurrence, node };
  });
  return materializeSelection({
    input,
    sourcePath,
    inventory,
    selected,
    signal,
  });
};

interface SelectedOccurrence {
  readonly occurrence: ArtifactOccurrence;
  readonly node: ArtifactNode;
}

interface ExtractedOccurrence {
  readonly artifact_id: string;
  readonly relative_path: string;
  readonly sha256: string;
  readonly bytes_written: number;
  readonly created: true;
}

const materializeSelection = async ({
  input,
  sourcePath,
  inventory,
  selected,
  signal,
}: {
  readonly input: ArtifactExtractionInput;
  readonly sourcePath: string;
  readonly inventory: ExtractionInventory;
  readonly selected: readonly SelectedOccurrence[];
  readonly signal: AbortSignal | undefined;
}): Promise<ArtifactExtractionResult> => {
  const byPath = new Map(
    selected.map((item) => [item.occurrence.logical_path, item]),
  );
  const reader = await createReader(sourcePath, input);
  const readerOwner: ArtifactResourceOwner = {
    kind: "reader" as const,
    reader,
    resource: `artifact reader for ${sourcePath}`,
  };
  let localReaderOwner: ArtifactResourceOwner | undefined = readerOwner;
  let output: SafeOutputTree | undefined;
  let completed: ArtifactExtractionResult | undefined;
  const extracted: ExtractedOccurrence[] = [];
  try {
    try {
      output = await SafeOutputTree.create(input.outputRoot);
    } catch (cause: unknown) {
      if (cause instanceof SafeOutputTreeCreationFailure) output = cause.tree;
      throw cause;
    }
    await writeSelectedEntries({
      reader,
      output,
      byPath,
      extracted,
      inventory,
      integrityPolicy: input.integrityPolicy,
      signal,
    });
    localReaderOwner = undefined;
    const closeAttempt = await input.resourceScope.release(readerOwner);
    if (closeAttempt.kind === "failed")
      throw ArtifactReaderFailure.withCleanup(
        closeAttempt.cause,
        ArtifactReaderFailure.cleanupObservation(
          closeAttempt.cause,
          readerOwner.resource,
        ),
      );
    extracted.sort((left, right) =>
      compareUnicodeCodePoints(left.relative_path, right.relative_path),
    );
    completed = createExtractionResult(input, inventory, selected, extracted);
    await output.commit();
    return completed;
  } catch (cause: unknown) {
    const cleanupFailures = await releaseExtractionOwners(
      input.resourceScope,
      localReaderOwner,
      output,
      input.outputRoot,
    );
    if (cleanupFailures.length > 0) {
      const observations = cleanupFailures.map(
        ({ cause: cleanupCause, resource }) =>
          ArtifactReaderFailure.cleanupObservation(cleanupCause, resource),
      );
      throw ArtifactReaderFailure.withCleanup(
        cause,
        {
          reason: observations.map(({ reason }) => reason).join("; "),
          resources: [
            ...new Set(observations.flatMap(({ resources }) => resources)),
          ],
        },
        output?.published === true && completed !== undefined
          ? { kind: "artifact-extraction", extraction: completed }
          : undefined,
      );
    }
    if (output?.published === true && completed !== undefined) return completed;
    throw cause;
  }
};

const writeSelectedEntries = async ({
  reader,
  output,
  byPath,
  extracted,
  inventory,
  integrityPolicy,
  signal,
}: {
  readonly reader: ArtifactReader;
  readonly output: SafeOutputTree;
  readonly byPath: Map<string, SelectedOccurrence>;
  readonly extracted: ExtractedOccurrence[];
  readonly inventory: ExtractionInventory;
  readonly integrityPolicy: ArtifactIntegrityPolicyName;
  readonly signal: AbortSignal | undefined;
}): Promise<void> => {
  const registry = new ArtifactPathRegistry();
  await visitArtifactTree(
    reader,
    async ({ reader: currentReader, entry, path, container: expandable }) => {
      // Traverse expanded PKG Payload/Scripts like inventory does, so nested
      // members are materialized instead of silently skipped. An expanded
      // member acts as a container: register it as a directory and leave its
      // archive bytes to its children, since a file and a directory cannot
      // share one output path.
      registry.add(path, expandable ? "directory" : entry.kind);
      if (expandable) return true;
      const selectedItem = byPath.get(path);
      if (selectedItem === undefined) {
        if (
          entry.contentUnavailable === true &&
          inventory.unavailablePaths.has(path)
        )
          return false;
        if (entry.kind === "file" || entry.kind === "slice")
          throw new ArtifactReaderFailure(
            "integrity",
            `Regular artifact entry is missing from inventory: ${path}`,
          );
        return false;
      }
      preflight(entry);
      const stream = await currentReader.open(entry, signal);
      const written = await output.write(
        path,
        stream,
        {
          sha256: selectedItem.node.sha256,
          bytes: selectedItem.node.size,
        },
        signal,
      );
      extracted.push({
        artifact_id: selectedItem.node.artifact_id,
        relative_path: written.relativePath,
        sha256: written.sha256,
        bytes_written: written.bytesWritten,
        created: true,
      });
      byPath.delete(path);
      return false;
    },
    { signal, integrity: integrityPolicy, expandAsar: false },
  );
  if (byPath.size > 0)
    throw new ArtifactReaderFailure(
      "integrity",
      `Inventoried regular artifact entries were not materialized: ${[...byPath.keys()].sort(compareUnicodeCodePoints).join(", ")}`,
    );
};

const releaseExtractionOwners = async (
  resourceScope: ArtifactResourceScope,
  readerOwner: ArtifactResourceOwner | undefined,
  output: SafeOutputTree | undefined,
  outputRoot: string,
): Promise<{ readonly cause: unknown; readonly resource: string }[]> => {
  const failures: { readonly cause: unknown; readonly resource: string }[] = [];
  if (readerOwner !== undefined) {
    const attempt = await resourceScope.release(readerOwner);
    if (attempt.kind === "failed")
      failures.push({ cause: attempt.cause, resource: readerOwner.resource });
  }
  if (output !== undefined) {
    const owner: ArtifactResourceOwner = {
      kind: "output-tree",
      tree: output,
      resource: outputRoot,
    };
    const attempt = await resourceScope.release(owner);
    if (attempt.kind === "failed")
      failures.push({ cause: attempt.cause, resource: owner.resource });
  }
  return failures;
};

const createExtractionResult = (
  input: ArtifactExtractionInput,
  inventory: ExtractionInventory,
  selected: readonly SelectedOccurrence[],
  extracted: readonly ExtractedOccurrence[],
): ArtifactExtractionResult => {
  const extractionSemantic = {
    source_manifest_id: inventory.manifest.manifest_id,
    selected_occurrence_ids: selected
      .map(({ occurrence }) => occurrence.occurrence_id)
      .sort(compareUnicodeCodePoints),
    files_sha256: digestCanonicalValue(extracted, "Artifact"),
    output_root_alias: "$OUTPUT_ROOT" as const,
  };
  return artifactExtractionResultSchema.parse({
    manifest: inventory.manifest,
    extraction_manifest: {
      ...extractionSemantic,
      extraction_id: `aex_${digestCanonicalValue(extractionSemantic, "Artifact")}`,
    },
    output_root: input.outputRoot,
    artifacts: extracted,
    containment_verified: true,
    cleanup: { attempted: false, verified: true, residual_paths: [] },
    provenance: [],
    integrity_contradictions: inventory.integrityContradictions,
    limitations: [
      "All available selected regular files were materialized; expanded PKG Payload/Scripts archives are represented by their extracted children and other nested archive contents by their containing file.",
      ...[...inventory.unavailablePaths].map(
        (path) =>
          `Unavailable member ${path} was not extracted; see its inventory occurrence for the reason.`,
      ),
      ...(inventory.integrityContradictions.length === 0
        ? []
        : [
            `${String(inventory.integrityContradictions.length)} extracted file(s) contradict declared integrity metadata; their bytes are observed-untrusted.`,
          ]),
    ],
  });
};

interface ExtractionInventory {
  readonly manifest: ArtifactGraphManifest;
  readonly integrityContradictions: readonly IntegrityContradiction[];
  readonly unavailablePaths: ReadonlySet<string>;
}

const ZIP_FORMATS = ["ipa", "apk", "msix", "appx", "zip"] as const;

const isZipFormat = (
  format: BinaryTarget["format"],
): format is (typeof ZIP_FORMATS)[number] =>
  (ZIP_FORMATS as readonly string[]).includes(format);

/**
 * Refuse a format without an extraction reader before inventory work starts.
 * The target kind, not the host, is unsupported by extraction. The error keeps
 * the caller's spelling of the path; I/O uses the canonical path.
 */
const requireExtractableFormat = async (
  path: string,
  input: Pick<ArtifactExtractionInput, "inputPath" | "inputFormat">,
): Promise<boolean> => {
  const format = input.inputFormat;
  const directory = (await lstat(path)).isDirectory();
  if (
    !directory &&
    format !== "asar" &&
    format !== "pkg" &&
    !isMachOFormat(format) &&
    !isZipFormat(format)
  )
    throw new AnalysisUnsupportedTargetError(
      "extract_artifact",
      input.inputPath,
      `Artifact format has no extraction reader: ${format}`,
    );
  return directory;
};

const createReader = async (
  path: string,
  input: Pick<
    ArtifactExtractionInput,
    "inputPath" | "inputFormat" | "environment"
  >,
): Promise<ArtifactReader> => {
  const format = input.inputFormat;
  if (await requireExtractableFormat(path, input))
    return new DirectoryArtifactReader(path);
  if (format === "asar") return new AsarArtifactReader(path);
  if (isZipFormat(format)) return new ZipArtifactReader(path, format);
  if (format === "pkg") return new XarArtifactReader(path);
  return new MachOSliceArtifactReader(path, input.environment);
};

const preflight = (entry: ArtifactEntry): void => {
  if ((entry.kind !== "file" && entry.kind !== "slice") || entry.encrypted)
    throw new ArtifactReaderFailure(
      "format",
      `Selected artifact entry cannot be read: ${entry.path}`,
    );
};
