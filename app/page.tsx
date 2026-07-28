import { getChatGPTUser } from "./chatgpt-auth";
import { GameApp } from "./GameApp";

export const dynamic = "force-dynamic";

export default async function Home() {
  const user = await getChatGPTUser();

  return (
    <GameApp
      identity={{
        displayName: user?.displayName ?? "内测指挥官",
        email: user?.email ?? "pilot@ember-protocol.local",
        authenticated: Boolean(user),
      }}
    />
  );
}
