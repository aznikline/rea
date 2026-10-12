import { realpath } from "node:fs/promises";
import type { BinaryTarget } from "../domain/binaryTargetTypes.js";
import type { AnalysisError } from "../domain/analysisErrorBase.js";
import { ProviderAdapterError } from "../domain/providerAdapterError.js";
import { jsonValueSchema } from "../domain/jsonValue.js";
import {
  inspectSignatureSchema,
  type NativeCommandInvocation,
} from "../domain/native/nativeInspection.js";
import { deriveSecurityFacets } from "./CodeSigningPolicy.js";
import {
  verifySignatureTarget,
  type SignatureTargetBinding,
} from "./SignatureTargetBinding.js";
import { omittedPrototypeKeysLimitation } from "../domain/propertyListKeys.js";
import { err, ok, type Result } from "../domain/result.js";
import {
  NativeCommandFailure,
  type NativeCommandCapture,
} from "./CommandRunner.js";
import { NATIVE_MACOS_PROVIDER_IDENTITY } from "./NativeMacOSProviderMetadata.js";
import type { NativeObservation } from "./NativeObservation.js";
import {
  signatureVerification,
  codesignOperationalFailure,
  codesignReasons,
} from "./CodesignVerification.js";
import { parseCodeSignature } from "./parsers/codesign.js";
import { parseSignatureEntitlements } from "./NativeSignatureEntitlements.js";
import {
  inspectSignatureSlices,
  unsignedSignatureCapture,
  type SignatureCapture,
} from "./NativeSignatureProbes.js";
import {
  SIGNATURE_POSTURE_LIMITATIONS,
  signedCodePath,
  stapledTicket,
} from "./NativeSignaturePosture.js";
import { inspectNestedCodePaths } from "./NativeNestedCode.js";

interface SignatureDisplays {
  readonly display: NativeCommandCapture;
  readonly requirements: NativeCommandCapture;
  readonly entitlements: NativeCommandCapture;
}

/** Display failures and unsigned observations use the same reason parser as verification. */
const signatureDisplays = async (
  displayPath: string,
  diagnosticPath: string,
  capture: SignatureCapture,
  signal?: AbortSignal,
): Promise<Result<SignatureDisplays, AnalysisError>> => {
  const display = await capture(["-d", "--verbose=4", displayPath], signal);
  if (!display.ok) return display;
  const requirements = await capture(["-d", "-r-", displayPath], signal);
  if (!requirements.ok) return requirements;
  const entitlements = await capture(
    ["-d", "--entitlements", ":-", displayPath],
    signal,
  );
  if (!entitlements.ok) return entitlements;
  for (const result of [
    display.value,
    requirements.value,
    entitlements.value,
  ]) {
    if (result.exitCode !== 0 && !unsignedSignatureCapture(result, displayPath))
      return err(
        new ProviderAdapterError(
          NATIVE_MACOS_PROVIDER_IDENTITY.id,
          "inspect_signature",
          {
            diagnostics: {
              path: diagnosticPath,
              tool: result.tool,
              arguments: [...result.arguments],
              exit_code: result.exitCode,
              signal: result.signal,
              raw_stdout: result.stdout,
              raw_stderr: result.stderr,
            },
            cause: new NativeCommandFailure(
              "codesign",
              "nonzero-exit",
              result.exitCode,
            ),
          },
        ),
      );
  }
  return ok({
    display: display.value,
    requirements: requirements.value,
    entitlements: entitlements.value,
  });
};

/**
 * Compose displays, independent slice knowledge, verification, and local
 * ticket evidence. A standalone binary's displays inspect the digest-verified
 * snapshot the binding holds; a bundle executable must be displayed in place
 * so codesign reports the sealed resource envelope, while verification,
 * nested code, and stapled-ticket evidence always need the live signed code
 * path's bundle context.
 */
export const inspectNativeSignature = async (options: {
  readonly target: BinaryTarget;
  readonly binding: SignatureTargetBinding;
  readonly capture: SignatureCapture;
  readonly invocation: (
    capture: NativeCommandCapture,
  ) => NativeCommandInvocation;
  readonly signal?: AbortSignal;
}): Promise<Result<NativeObservation, AnalysisError>> => {
  const { target, binding, capture, signal } = options;
  const code = signedCodePath(target);
  const displayPath = code === target.path ? binding.snapshotPath : target.path;
  const displays = await signatureDisplays(
    displayPath,
    target.path,
    capture,
    signal,
  );
  if (!displays.ok) return displays;
  const { display, requirements, entitlements } = displays.value;
  const unsigned = unsignedSignatureCapture(display, displayPath);
  let canonical: string[] = [];
  try {
    canonical = [await realpath(displayPath)];
  } catch {
    /* The display retains the observed path. */
  }
  const parsed = parseCodeSignature(display.stderr, unsigned, [
    displayPath,
    ...canonical,
  ]);
  const entitlementValue = parseSignatureEntitlements(entitlements.stdout);
  const verify = (path: string) =>
    capture(["--verify", "--deep", "--strict", "--verbose=2", path], signal);
  const verified = await verify(code);
  if (!verified.ok) return verified;
  const captures = [display, requirements, entitlements, verified.value];
  let appleOrigin = false;
  let appleOriginFailure: string | undefined;
  if (!unsigned && (parsed.code_directory?.platform_identifier ?? 0) !== 0) {
    const anchor = await capture(["--verify", "-R=anchor apple", code], signal);
    if (!anchor.ok) return anchor;
    captures.push(anchor.value);
    appleOrigin = anchor.value.exitCode === 0;
    if (!appleOrigin) {
      const reason = codesignReasons(anchor.value, code)
        .filter((line) => line.trim().length > 0)
        .join("\n");
      appleOriginFailure = reason || `codesign exited ${anchor.value.exitCode}`;
    }
  }
  const slices = await inspectSignatureSlices(
    target,
    {
      displayPath,
      format: parsed.format,
      requirements,
      entitlements,
      unsigned,
    },
    capture,
    signal,
  );
  if (!slices.ok) return slices;
  captures.push(...slices.value.captures);
  const aggregateUnsigned =
    slices.value.signed === undefined ? unsigned : !slices.value.signed;
  // Verification is independent evidence: uncertain display probes must not
  // erase an explicit signature failure from the verifier.
  const reportedVerification = signatureVerification(
    verified.value,
    code,
    aggregateUnsigned,
  );
  const nestedPaths = await inspectNestedCodePaths(
    reportedVerification,
    signal,
  );
  const verification = nestedPaths.progressAmbiguous
    ? signatureVerification(
        verified.value,
        code,
        aggregateUnsigned,
        "ambiguous",
      )
    : reportedVerification;
  const limitations = [
    ...parsed.limitations,
    ...SIGNATURE_POSTURE_LIMITATIONS,
    ...slices.value.limitations,
    ...nestedPaths.limitations,
  ];
  if (entitlementValue.omittedPrototypeKeys !== 0)
    limitations.push(
      `Entitlements: ${omittedPrototypeKeysLimitation(entitlementValue.omittedPrototypeKeys)}`,
    );
  if (appleOriginFailure !== undefined)
    limitations.push(`Apple-origin check failed: ${appleOriginFailure}`);
  if (verification.status === "unknown")
    limitations.push(
      "Signature verification is inconclusive (permission, I/O or unrecognized diagnostic); this is not a proven broken signature.",
    );
  else if (codesignOperationalFailure(verified.value, code))
    limitations.push(
      "Some code could not be verified due to operational diagnostics; definitive signature failures elsewhere still prove invalidity.",
    );
  let mainInvalid =
    verification.status === "invalid" || verification.status === "unknown";
  if (mainInvalid && !unsigned && code !== target.path) {
    const main = await verify(target.path);
    if (!main.ok) return main;
    captures.push(main.value);
    mainInvalid = main.value.exitCode !== 0;
  }
  const provenance = captures.map(options.invocation);
  const ticket = await stapledTicket(target, signal);
  const version = await verifySignatureTarget(target, binding, signal);
  if (!version.ok) return version;
  const facets = deriveSecurityFacets({
    signed: !aggregateUnsigned,
    codeDirectory: parsed.code_directory,
    entitlements: entitlementValue.value,
    entitlementsKnown: unsigned || entitlements.exitCode === 0,
    mixedSlices: slices.value.mixed,
    appleOrigin,
    signatureInvalid: mainInvalid,
  });
  const result = inspectSignatureSchema.parse({
    ...parsed,
    signed: !aggregateUnsigned,
    designated_requirement:
      /designated\s*=>\s*(.+)$/mu.exec(requirements.stdout)?.[1] ?? null,
    entitlements: entitlementValue.value,
    verification,
    stapled_ticket: ticket,
    security_facets: facets,
    provenance,
    limitations,
  });
  return ok({
    result: jsonValueSchema.parse(result),
    limitations: result.limitations,
    locations: [],
  });
};
