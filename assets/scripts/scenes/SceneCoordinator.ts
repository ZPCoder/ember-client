import { _decorator, Component, director } from "cc";

const { ccclass } = _decorator;

export const CLIENT_SCENES = [
  "BootLogin",
  "Collection",
  "DeckBuilder",
  "PackOpening",
  "Battle",
  "OnlineLobby",
  "Profile",
] as const;

export type ClientScene = (typeof CLIENT_SCENES)[number];

export class SceneCoordinator {
  #transitioning = false;

  async go(scene: ClientScene): Promise<void> {
    if (this.#transitioning) {
      return;
    }
    this.#transitioning = true;
    try {
      await new Promise<void>((resolve, reject) => {
        director.preloadScene(scene, (error) => {
          if (error) {
            reject(error);
            return;
          }
          director.loadScene(scene, (loadError) => {
            if (loadError) {
              reject(loadError);
              return;
            }
            resolve();
          });
        });
      });
    } finally {
      this.#transitioning = false;
    }
  }
}

abstract class RoutedSceneController extends Component {
  protected readonly router = new SceneCoordinator();
}

@ccclass("BootLoginSceneController")
export class BootLoginSceneController extends RoutedSceneController {
  enterCollection(): void {
    void this.router.go("Collection");
  }
}

@ccclass("CollectionSceneController")
export class CollectionSceneController extends RoutedSceneController {
  enterDeckBuilder(): void {
    void this.router.go("DeckBuilder");
  }
}

@ccclass("DeckBuilderSceneController")
export class DeckBuilderSceneController extends RoutedSceneController {
  enterLobby(): void {
    void this.router.go("OnlineLobby");
  }
}

@ccclass("PackOpeningSceneController")
export class PackOpeningSceneController extends RoutedSceneController {
  returnToCollection(): void {
    void this.router.go("Collection");
  }
}

@ccclass("BattleSceneController")
export class BattleSceneController extends RoutedSceneController {
  leaveBattle(): void {
    void this.router.go("OnlineLobby");
  }
}

@ccclass("OnlineLobbySceneController")
export class OnlineLobbySceneController extends RoutedSceneController {
  enterAiOrPvpBattle(): void {
    void this.router.go("Battle");
  }
}

@ccclass("ProfileSceneController")
export class ProfileSceneController extends RoutedSceneController {
  returnToCollection(): void {
    void this.router.go("Collection");
  }
}
