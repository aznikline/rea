import { ArtifactBudgetExceeded } from "../ArtifactDecodedBudget.js";
import {
  annotateEnglishUnicodeCaseCollisions,
  ArtifactPathRegistry,
} from "../ArtifactPaths.js";
import { AsarArtifactReader } from "../AsarArtifactReader.js";
import { visitArtifactTree } from "../ArtifactTraversal.js";
import {
  ArtifactReaderFailure,
  type ArtifactEntry,
  type ArtifactReader,
  type ArtifactChecksumObservation,
} from "../ArtifactReader.js";
import type { ArtifactNode } from "../../domain/artifactGraph.js";
import {
  classifyArtifactContent,
  classifyArtifactBytes,
  createArtifactNode,
  createOccurrence,
  noteUnreadContainerSuffix,
  resolveOccurrenceParents,
  type MutableOccurrence,
} from "./ArtifactGraphConstruction.js";
import {
  STRICT_INTEGRITY_POLICY,
  type ArtifactIntegrityPolicy,
} from "./types.js";
import { hashReadable } from "../ArtifactHash.js";

export interface PendingIntegrityContradiction {
  readonly logicalPath: string;
  readonly declaredSha256: string;
  readonly observedSha256: string;
  readonly entryKind: "file" | "slice";
  readonly unpacked: boolean;
}

const UNAVAILABLE_UNPACKED_LIMITATION =
  "ASAR unpacked companion bytes were unavailable; no content hash or child artifact was produced.";

const emptyScan = (): {
  readonly nodes: Map<string, ArtifactNode>;
  readonly occurrences: MutableOccurrence[];
  readonly pendingContradictions: PendingIntegrityContradiction[];
} => ({ nodes: new Map(), occurrences: [], pendingContradictions: [] });

interface ScanContext {
  readonly reader: ArtifactReader;
  readonly signal: AbortSignal | undefined;
  readonly integrity: ArtifactIntegrityPolicy;
  readonly nodes: Map<string, ArtifactNode>;
  readonly occurrences: MutableOccurrence[];
  readonly pendingContradictions: PendingIntegrityContradiction[];
  readonly occurrenceByPath: Map<string, MutableOccurrence>;
  readonly registry: ArtifactPathRegistry;
  readonly expandedContainerIds: Set<string>;
  readonly ownedReaders: ArtifactReader[];
  /** Observed member digests for containers the visitor allowed to expand. */
  readonly expandedContainerSha256: Map<string, string>;
}

export const scanReader = async (
  reader: ArtifactReader | undefined,
  ownedReaders: ArtifactReader[],
  signal?: AbortSignal,
  integrity: ArtifactIntegrityPolicy = STRICT_INTEGRITY_POLICY,
): Promise<{
  readonly nodes: Map<string, ArtifactNode>;
  readonly occurrences: MutableOccurrence[];
  readonly pendingContradictions: PendingIntegrityContradiction[];
  readonly caseCollisionLimitation: string | undefined;
}> => {
  const { nodes, occurrences, pendingContradictions } = emptyScan();
  if (reader === undefined)
    return {
      nodes,
      occurrences,
      pendingContradictions,
      caseCollisionLimitation: undefined,
    };
  const context: ScanContext = {
    reader,
    signal,
    integrity,
    nodes,
    occurrences,
    pendingContradictions,
    occurrenceByPath: new Map<string, MutableOccurrence>(),
    registry: new ArtifactPathRegistry(),
    expandedContainerIds: new Set<string>(),
    ownedReaders,
    expandedContainerSha256: new Map<string, string>(),
  };
  await visitArtifactEntries(context, reader);
  // Archive directories may appear after their children. Resolve containment
  // against the complete index before directory identities are materialized.
  resolveOccurrenceParents(
    occurrences,
    context.occurrenceByPath,
    context.expandedContainerIds,
  );
  return {
    nodes,
    occurrences,
    pendingContradictions,
    caseCollisionLimitation: annotateEnglishUnicodeCaseCollisions(occurrences),
  };
};

const visitArtifactEntries = async (
  context: ScanContext,
  currentReader: ArtifactReader,
): Promise<void> => {
  await visitArtifactTree(
    currentReader,
    async ({ reader, entry, path: logicalPath, container: expandable }) => {
      context.registry.add(logicalPath, expandable ? "directory" : entry.kind);
      const occurrence = createOccurrence(entry, logicalPath, null);
      let digested: DigestedEntry | undefined;
      try {
        digested = await digestArtifactEntry(
          context,
          reader,
          entry,
          logicalPath,
        );
      } catch (cause: unknown) {
        if (!isUnavailableUnpackedEntry(cause, entry)) {
          // A streamed CRC, size-bound, or format failure is per-member
          // evidence loss under record-and-continue: keep the occurrence
          // unavailable with its diagnostic, without inventing a node.
          if (
            context.integrity.mode !== "record-and-continue" ||
            cause instanceof ArtifactBudgetExceeded ||
            !(cause instanceof ArtifactReaderFailure) ||
            (cause.reason !== "integrity" &&
              cause.reason !== "limit" &&
              cause.reason !== "format")
          )
            throw cause;
          occurrence.hash_status = "unavailable";
          occurrence.limitations.push(
            `Member content could not be verified: ${cause.message}`,
          );
          context.occurrences.push(occurrence);
          context.occurrenceByPath.set(logicalPath, occurrence);
          return false;
        }
        occurrence.hash_status = "unavailable";
        occurrence.limitations.push(UNAVAILABLE_UNPACKED_LIMITATION);
      }
      if (digested === undefined) noteUnreadContainerSuffix(occurrence);
      else {
        context.nodes.set(digested.node.artifact_id, digested.node);
        occurrence.artifact_id = digested.node.artifact_id;
        occurrence.artifact_kind = digested.classification.kind;
        occurrence.artifact_format = digested.classification.format;
        occurrence.hash_status = digested.mismatched
          ? "mismatched"
          : "verified";
        if (digested.mismatched)
          occurrence.limitations.push(
            "Declared integrity metadata contradicts observed bytes.",
            ...digested.mismatchDetails,
          );
      }
      context.occurrences.push(occurrence);
      context.occurrenceByPath.set(logicalPath, occurrence);
      if (
        expandable &&
        digested !== undefined &&
        !digested.mismatched &&
        (entry.nestedArchive === "gzip-cpio" ||
          digested.classification.format === "asar")
      ) {
        context.expandedContainerSha256.set(
          logicalPath,
          digested.node.sha256,
        );
        // Only traversed containers can own members, not opaque archive-named files.
        context.expandedContainerIds.add(occurrence.occurrence_id);
        return true;
      }
      return false;
    },
    {
      signal: context.signal,
      integrity: context.integrity.mode,
      // Nested readers remain owned by the inventory until its complete
      // observation is built; the scope releases them afterwards.
      retainReaders: context.ownedReaders,
      prepareNested: async (nested, item) => {
        if (nested instanceof AsarArtifactReader)
          await nested.prepareContainer(
            context.expandedContainerSha256.get(item.path),
            context.signal,
          );
      },
    },
  );
};

interface DigestedEntry {
  readonly node: ArtifactNode;
  readonly mismatched: boolean;
  readonly classification: ReturnType<typeof classifyArtifactContent>;
  /** Declared and observed values of a non-SHA-256 checksum that disagreed. */
  readonly mismatchDetails: readonly string[];
}

const checksumDescription = ({
  representation,
  algorithm,
  declared,
  observed,
}: ArtifactChecksumObservation): string =>
  `Declared ${representation} ${algorithm} ${declared} disagrees with observed ${observed}.`;

const entryIntegrityFailure = (
  entry: ArtifactEntry,
  logicalPath: string,
  observed: {
    readonly sha256: string;
    readonly checksumMismatches: readonly ArtifactChecksumObservation[];
  },
): ArtifactReaderFailure => {
  const mismatchDetails = observed.checksumMismatches.map(checksumDescription);
  return new ArtifactReaderFailure(
    "integrity",
    `Artifact integrity metadata disagrees with content: ${logicalPath}${mismatchDetails.length === 0 ? "" : ` (${mismatchDetails.join(" ")})`}`,
    undefined,
    {
      logicalPath,
      declaredSha256: entry.declaredSha256,
      calculatedSha256: observed.sha256,
      unpacked: entry.unpacked,
      ...(observed.checksumMismatches.length === 0
        ? {}
        : { checksumMismatches: observed.checksumMismatches }),
    },
  );
};

const digestArtifactEntry = async (
  context: ScanContext,
  currentReader: ArtifactReader,
  entry: ArtifactEntry,
  logicalPath: string,
): Promise<DigestedEntry | undefined> => {
  if (
    (entry.kind !== "file" && entry.kind !== "slice") ||
    entry.encrypted ||
    entry.contentUnavailable === true
  )
    return undefined;
  const checksum = entry.declaredChecksum;
  const digest = await hashReadable(
    await currentReader.open(entry, context.signal),
    context.signal,
    checksum?.algorithm,
  );
  const sha256Mismatch =
    entry.declaredSha256 !== null && entry.declaredSha256 !== digest.sha256;
  const checksumMismatch =
    checksum !== undefined && checksum.value !== digest.also;
  const storedMismatches = (
    currentReader.integrityObservations?.(entry) ?? []
  ).filter(({ declared, observed }) => declared !== observed);
  const mismatched =
    sha256Mismatch || checksumMismatch || storedMismatches.length > 0;
  const checksumMismatches = [
    ...(checksumMismatch
      ? [
          {
            representation: "decoded" as const,
            algorithm: checksum.algorithm,
            declared: checksum.value,
            observed: digest.also ?? "unavailable",
          },
        ]
      : []),
    ...storedMismatches,
  ];
  if (mismatched && context.integrity.mode === "fail")
    throw entryIntegrityFailure(entry, logicalPath, {
      sha256: digest.sha256,
      checksumMismatches,
    });
  if (sha256Mismatch && entry.declaredSha256 !== null)
    context.pendingContradictions.push({
      logicalPath,
      declaredSha256: entry.declaredSha256,
      observedSha256: digest.sha256,
      entryKind: entry.kind,
      unpacked: entry.unpacked,
    });
  const classified =
    entry.kind === "slice"
      ? ({ kind: "universal-slice", format: "mach-o" } as const)
      : classifyArtifactContent(logicalPath, digest.prefix, digest.bytes);
  return {
    node: createArtifactNode({
      sha256: digest.sha256,
      size: digest.bytes,
      format: classifyArtifactBytes(digest.prefix, digest.bytes),
      contentState: "embedded",
    }),
    mismatched,
    classification: classified,
    mismatchDetails: checksumMismatches.map(checksumDescription),
  };
};

const isUnavailableUnpackedEntry = (
  cause: unknown,
  entry: ArtifactEntry,
): boolean =>
  entry.unpacked &&
  cause instanceof ArtifactReaderFailure &&
  cause.reason === "unavailable";
