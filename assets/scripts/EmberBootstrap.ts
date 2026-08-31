import { _decorator, Camera, Color, Component, DirectionalLight, Node, Vec3, director } from "cc";

import { assertQaIdentityGate, type QaIdentityContext } from "./auth/ChannelAuthPort";
import { RemoteBundleLoader } from "./bundles/RemoteBundleLoader";
import {
  ModularHeroFactory,
  ProceduralBattlefieldFactory,
} from "./presentation/ProceduralArena";

const { ccclass } = _decorator;

/**
 * Creator scene bootstrap. It builds an editor-independent vertical-slice board
 * from primitives; production scenes replace only presentation assets.
 */
@ccclass("EmberBootstrap")
export class EmberBootstrap extends Component {
  readonly bundles = new RemoteBundleLoader();

  protected override start(): void {
    const scene = director.getScene();
    if (!scene || scene.getChildByName("ProceduralBattlefield")) {
      return;
    }
    const battlefield = new ProceduralBattlefieldFactory().create();
    scene.addChild(battlefield.root);

    const heroFactory = new ModularHeroFactory();
    const playerHero = heroFactory.create("ember");
    battlefield.playerHeroAnchor.addChild(playerHero.root);
    const opponentHero = heroFactory.create("astral");
    battlefield.opponentHeroAnchor.addChild(opponentHero.root);

    const cameraNode = new Node("BattleCamera");
    cameraNode.setPosition(0, 8.2, 10.8);
    cameraNode.setRotationFromEuler(-36, 0, 0);
    cameraNode.addComponent(Camera);
    scene.addChild(cameraNode);

    const lightNode = new Node("MysticKeyLight");
    lightNode.setRotationFromEuler(-55, -35, 0);
    const light = lightNode.addComponent(DirectionalLight);
    light.color = new Color(168, 189, 255, 255);
    light.illuminance = 18_000;
    scene.addChild(lightNode);
  }

  validateBuildIdentity(context: Readonly<QaIdentityContext>): void {
    assertQaIdentityGate(context);
  }

  protected override onDestroy(): void {
    this.bundles.releaseAllTransient();
  }
}
