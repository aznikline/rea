import type { JsonValue } from "../domain/jsonValue.js";
import type { EvidenceLocation } from "../domain/evidence.js";

/** Provider observation before shared execution/Evidence projection. */
export interface NativeObservation {
  readonly result: JsonValue;
  readonly limitations: readonly string[];
  readonly locations: readonly EvidenceLocation[];
}
