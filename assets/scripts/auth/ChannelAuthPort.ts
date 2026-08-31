export type ClientPlatform = "4399-h5" | "chatgpt" | "device-compat" | "internal-qa";

export interface ChannelTicketExchange {
  readonly platform: ClientPlatform;
  readonly ticket: string;
  readonly clientVersion: string;
}

export interface ShortLivedSession {
  readonly accessToken: string;
  readonly expiresAt: string;
  readonly playerId: string;
  readonly configVersion: string;
}

export interface ChannelAuthGateway {
  exchange(request: Readonly<ChannelTicketExchange>): Promise<Readonly<ShortLivedSession>>;
}

/** Only forwards an opaque one-time ticket; a client-supplied UID is forbidden. */
export function channelLogin(
  gateway: ChannelAuthGateway,
  request: Readonly<ChannelTicketExchange>,
): Promise<Readonly<ShortLivedSession>> {
  if (!request.ticket.trim()) {
    return Promise.reject(new Error("channel-ticket-required"));
  }
  if (
    Object.prototype.hasOwnProperty.call(request, "uid") ||
    Object.prototype.hasOwnProperty.call(request, "playerId")
  ) {
    return Promise.reject(new Error("client-channel-uid-forbidden"));
  }
  return gateway.exchange(Object.freeze({ ...request }));
}

export interface QaIdentityContext {
  readonly buildTarget: "web" | "windows" | "macos";
  readonly environment: "development" | "internal-qa" | "staging" | "production";
  readonly identityProvider: ClientPlatform;
  readonly publicDistribution: boolean;
}

export function assertQaIdentityGate(context: Readonly<QaIdentityContext>): void {
  if (context.buildTarget === "web") {
    return;
  }
  if (
    context.environment !== "internal-qa" ||
    context.identityProvider !== "internal-qa" ||
    context.publicDistribution
  ) {
    throw new Error("desktop-build-must-use-internal-qa-identity");
  }
}

export const CHANNEL_CAPABILITIES = Object.freeze({
  supportsLogin: true,
  supportsSensitiveWords: true,
  supportsRoleQuery: true,
  supportsGiftPacks: true,
  supportsPayment: false,
});
