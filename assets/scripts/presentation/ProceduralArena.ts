import {
  Color,
  Material,
  MeshRenderer,
  Node,
  Texture2D,
  Vec3,
  primitives,
  tween,
  utils,
} from "cc";

import { findHeroForm, type HeroFormId } from "./HeroForms";

export interface SharedHeroRig {
  readonly root: Node;
  readonly hips: Node;
  readonly spine: Node;
  readonly headSocket: Node;
  readonly leftHandSocket: Node;
  readonly rightHandSocket: Node;
  readonly weaponSocket: Node;
}

export interface ProceduralBattlefield {
  readonly root: Node;
  readonly emberCore: Node;
  readonly slots: readonly Node[];
  readonly playerHeroAnchor: Node;
  readonly opponentHeroAnchor: Node;
}

function standardMaterial(name: string, color: Readonly<Color>, emission = 0): Material {
  const material = new Material();
  material.name = name;
  material.initialize({ effectName: "builtin-standard" });
  material.setProperty("mainColor", color);
  material.setProperty("metallic", 0.48);
  material.setProperty("roughness", 0.38);
  if (emission > 0) {
    material.setProperty("emissive", color);
    material.setProperty("emissiveScale", emission);
  }
  return material;
}

function primitiveNode(
  name: string,
  geometry: Parameters<typeof utils.createMesh>[0],
  material: Material,
  scale?: Readonly<Vec3>,
): Node {
  const node = new Node(name);
  const renderer = node.addComponent(MeshRenderer);
  renderer.mesh = utils.createMesh(geometry);
  renderer.material = material;
  if (scale) {
    node.setScale(scale);
  }
  return node;
}

export class ProceduralBattlefieldFactory {
  create(): ProceduralBattlefield {
    const root = new Node("ProceduralBattlefield");
    const obsidian = standardMaterial("obsidian", new Color(13, 16, 29, 255));
    const starMetal = standardMaterial("star-metal", new Color(42, 56, 87, 255), 0.12);
    const ember = standardMaterial("ember-core", new Color(255, 76, 26, 255), 2.4);

    const board = primitiveNode(
      "DarkMysticTechnologyBoard",
      primitives.box({ width: 15, height: 0.55, length: 9 }),
      obsidian,
    );
    board.setPosition(0, -0.35, 0);
    root.addChild(board);

    const innerTable = primitiveNode(
      "StarChartPlate",
      primitives.cylinder(3.8, 3.8, 0.09, { radialSegments: 48 }),
      starMetal,
    );
    innerTable.setPosition(0, 0, 0);
    root.addChild(innerTable);

    const emberCore = primitiveNode(
      "EmberCore",
      primitives.sphere(0.48, { segments: 24 }),
      ember,
    );
    emberCore.setPosition(0, 0.46, 0);
    root.addChild(emberCore);
    tween(emberCore)
      .by(2.4, { eulerAngles: new Vec3(0, 180, 0) })
      .union()
      .repeatForever()
      .start();

    const slots: Node[] = [];
    for (let side = 0; side < 2; side += 1) {
      for (let index = 0; index < 7; index += 1) {
        const slot = primitiveNode(
          `CardSlot-${side}-${index}`,
          primitives.box({ width: 1.55, height: 0.08, length: 2.12 }),
          starMetal,
        );
        slot.setPosition((index - 3) * 1.82, 0.1, side === 0 ? 2.15 : -2.15);
        root.addChild(slot);
        slots.push(slot);
      }
    }

    // Small emissive stars form a readable chart without a texture dependency.
    for (let index = 0; index < 24; index += 1) {
      const angle = (index / 24) * Math.PI * 2;
      const radius = 2.1 + (index % 4) * 0.34;
      const star = primitiveNode(
        `Star-${index}`,
        primitives.sphere(index % 5 === 0 ? 0.055 : 0.025, { segments: 8 }),
        starMetal,
      );
      star.setPosition(Math.cos(angle) * radius, 0.13, Math.sin(angle) * radius);
      root.addChild(star);
    }

    const playerHeroAnchor = new Node("PlayerHeroAnchor");
    playerHeroAnchor.setPosition(-6.35, 0.15, 2.55);
    root.addChild(playerHeroAnchor);
    const opponentHeroAnchor = new Node("OpponentHeroAnchor");
    opponentHeroAnchor.setPosition(6.35, 0.15, -2.55);
    opponentHeroAnchor.setRotationFromEuler(0, 180, 0);
    root.addChild(opponentHeroAnchor);

    return Object.freeze({ root, emberCore, slots, playerHeroAnchor, opponentHeroAnchor });
  }
}

/** Shared hierarchical placeholder rig used by every faction module. */
export class ModularHeroFactory {
  create(formId: HeroFormId): SharedHeroRig {
    const form = findHeroForm(formId);
    const primary = standardMaterial(`${form.id}-primary`, form.primary, 0.18);
    const secondary = standardMaterial(`${form.id}-secondary`, form.secondary, 0.28);
    const root = new Node(`Hero-${form.id}`);
    const hips = new Node("hips");
    hips.setPosition(0, 0.72, 0);
    root.addChild(hips);
    const spine = primitiveNode(
      `armor-${form.armorModule}`,
      primitives.capsule(0.45, 0.45, 1.1, { sides: 16, heightSegments: 4 }),
      primary,
    );
    spine.setPosition(0, 0.72, 0);
    hips.addChild(spine);

    const headSocket = new Node("head-socket");
    headSocket.setPosition(0, 1.48, 0);
    hips.addChild(headSocket);
    const head = primitiveNode(
      `head-${form.headModule}`,
      form.headModule === "horns"
        ? primitives.cylinder(0.36, 0.36, 0.58, { radialSegments: 10 })
        : primitives.sphere(0.38, { segments: 16 }),
      secondary,
    );
    headSocket.addChild(head);

    const leftHandSocket = new Node("left-hand-socket");
    leftHandSocket.setPosition(-0.63, 0.9, 0);
    hips.addChild(leftHandSocket);
    const rightHandSocket = new Node("right-hand-socket");
    rightHandSocket.setPosition(0.63, 0.9, 0);
    hips.addChild(rightHandSocket);
    const weaponSocket = new Node("weapon-socket");
    rightHandSocket.addChild(weaponSocket);
    const weapon = primitiveNode(
      `weapon-${form.weaponModule}`,
      form.weaponModule === "orb"
        ? primitives.sphere(0.22, { segments: 12 })
        : primitives.box({ width: 0.14, height: 1.28, length: 0.14 }),
      secondary,
    );
    weapon.setPosition(0, 0.25, 0);
    weaponSocket.addChild(weapon);

    tween(spine)
      .by(1.8, { position: new Vec3(0, 0.045, 0) }, { easing: "sineInOut" })
      .by(1.8, { position: new Vec3(0, -0.045, 0) }, { easing: "sineInOut" })
      .union()
      .repeatForever()
      .start();
    return Object.freeze({
      root,
      hips,
      spine,
      headSocket,
      leftHandSocket,
      rightHandSocket,
      weaponSocket,
    });
  }
}

export class CardEntityFactory {
  create(cardId: string, cardFace?: Texture2D): Node {
    const back = standardMaterial("card-edge", new Color(26, 24, 39, 255));
    const card = primitiveNode(
      `CardEntity-${cardId}`,
      primitives.box({ width: 1.3, height: 0.08, length: 1.85 }),
      back,
    );
    if (cardFace) {
      const faceMaterial = standardMaterial("card-face", Color.WHITE);
      faceMaterial.setProperty("albedoMap", cardFace);
      const face = primitiveNode(
        "Existing2DCardFace",
        primitives.quad(),
        faceMaterial,
        new Vec3(1.2, 1, 1.75),
      );
      face.setPosition(0, 0.047, 0);
      face.setRotationFromEuler(-90, 0, 0);
      card.addChild(face);
    }
    return card;
  }
}
