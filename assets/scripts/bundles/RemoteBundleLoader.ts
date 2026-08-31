import { Asset, AssetManager, assetManager } from "cc";

export type BundleId =
  | "bootstrap"
  | "common-ui"
  | "battlefield"
  | "heroes-01"
  | "heroes-02"
  | "heroes-03"
  | "heroes-04"
  | "card-thumbnails"
  | "card-full";

export interface ClientBundleManifestEntry {
  readonly id: BundleId;
  readonly version: string;
  readonly sha256: string;
  readonly url: string;
  readonly size: number;
  readonly includedInBoot: boolean;
}

export interface ClientBundleManifest {
  readonly configVersion: string;
  readonly minimumClientVersion: string;
  readonly bundles: readonly ClientBundleManifestEntry[];
}

interface LoadedBundle {
  readonly bundle: AssetManager.Bundle;
  references: number;
}

export interface BundleIntegrityVerifier {
  /**
   * Verifies the immutable archive/resource manifest before Creator receives
   * the URL. Implementations live in the config/SDK adapter and must fail closed.
   */
  verify(entry: Readonly<ClientBundleManifestEntry>): Promise<void>;
}

export class RemoteBundleLoader {
  readonly #loaded = new Map<BundleId, LoadedBundle>();
  readonly #integrityVerifier: BundleIntegrityVerifier | null;
  #manifest: Readonly<ClientBundleManifest> | null = null;

  constructor(integrityVerifier?: BundleIntegrityVerifier) {
    this.#integrityVerifier = integrityVerifier ?? null;
  }

  configure(manifest: Readonly<ClientBundleManifest>): void {
    for (const entry of manifest.bundles) {
      if (!/^[a-f0-9]{64}$/i.test(entry.sha256) || entry.size < 0) {
        throw new Error(`invalid-bundle-manifest:${entry.id}`);
      }
    }
    this.#manifest = Object.freeze({
      ...manifest,
      bundles: Object.freeze(manifest.bundles.map((entry) => Object.freeze({ ...entry }))),
    });
  }

  async acquire(id: BundleId): Promise<AssetManager.Bundle> {
    const current = this.#loaded.get(id);
    if (current) {
      current.references += 1;
      return current.bundle;
    }
    const entry = this.#entry(id);
    if (!entry.includedInBoot) {
      if (!this.#integrityVerifier) {
        throw new Error(`remote-bundle-integrity-verifier-missing:${id}`);
      }
      await this.#integrityVerifier.verify(entry);
    }
    const bundle = await new Promise<AssetManager.Bundle>((resolve, reject) => {
      assetManager.loadBundle(entry.url, { version: entry.version }, (error, loaded) => {
        if (error || !loaded) {
          reject(error ?? new Error(`bundle-load-failed:${id}`));
          return;
        }
        resolve(loaded);
      });
    });
    this.#loaded.set(id, { bundle, references: 1 });
    return bundle;
  }

  release(id: BundleId): void {
    const current = this.#loaded.get(id);
    if (!current) {
      return;
    }
    current.references -= 1;
    if (current.references > 0 || id === "bootstrap") {
      return;
    }
    current.bundle.releaseAll();
    assetManager.removeBundle(current.bundle);
    this.#loaded.delete(id);
  }

  releaseAsset(asset: Asset): void {
    assetManager.releaseAsset(asset);
  }

  releaseAllTransient(): void {
    for (const id of [...this.#loaded.keys()]) {
      if (id !== "bootstrap") {
        const loaded = this.#loaded.get(id);
        if (loaded) {
          loaded.references = 1;
        }
        this.release(id);
      }
    }
  }

  #entry(id: BundleId): Readonly<ClientBundleManifestEntry> {
    const entry = this.#manifest?.bundles.find((candidate) => candidate.id === id);
    if (!entry) {
      throw new Error(`bundle-not-configured:${id}`);
    }
    return entry;
  }
}
