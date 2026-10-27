# What the zombies look like

Why `npcs/zz_zombie_view.gd` draws zombies the way it does, and why the obvious alternative is wrong in each case. The classes are `ZzZombieView` (the picture), `ZzZombieBody` (what is replicated: `kind`, `variant`, `anim`, `flags`, `health`, and `death` once it is dead) and `tools/build_zombie_models.py` (the models).

## Where the models come from

Quaternius' [Zombie Apocalypse Kit](https://quaternius.com/packs/zombieapocalypsekit.html) (CC0 1.0), the same kit the family's people (dot-player-char's `people/`, which the survivors are drawn as) come from: three zombies (`Zombie_Basic`, `Zombie_Chubby`, `Zombie_Arm`) and four survivors (`Matt`, `Lis`, `Sam`, `Shaun`), all on one 43-to-50-bone rig with the same bone names, with sixteen clips on the zombies (idle, walk, run, run with arms out, three attacks, hit, death, crawl, three jumps). Kenney's bundle has no animated zombie, and its animated characters were the old picture: one body in three shirts, which the first play test called out. The kit's fourth zombie (`Zombie_Ribcage`, a pair of legs carrying a ribcage) is not used.

The kit is not vendored. `tools/build_zombie_models.py` is the source: download the kit's `Characters/glTF` folder and run it in Blender. It keeps the one skinned mesh of each body (the survivors carry eleven weapons on a finger bone), joins it to one surface, decimates it to 35% (two to three thousand triangles), paints three noise fields into the vertex colours (dirt, blood with less on the head, rot), renames the clips, and exports without the atlas. Only the zombies keep clips; the survivor bodies are a quarter of the size without them.

## One rig, two rest poses

The survivor bodies are driven by `zombie_basic`'s clips, which is what makes them shamble rather than jog. A clip stores where each bone **is**, not how far it moved, and the survivors' rest pose is not the zombie's (their chest bone points up, the zombie's leans forward along the chest). Played as they are, the zombie's clips bent every survivor double at the waist. `_retarget` moves each key off the zombie's rest and onto the survivor's (`rotation = to_rest * from_rest^-1 * key`, a position turned the same way about the new rest), once per body, shared by every zombie drawn with it.

## A crowd is not one person

A common's 16-bit variant picks its body (five), skin (eight dead tones), clothes (twelve top and bottom pairs), hair, height (90 to 107%), girth, how much blood and how much dirt. The palette shader swaps the body's own atlas colours (`WEARS`, measured by `tools/zombie_palette.gd`) for the look's, then darkens by the dirt noise and paints blood where two noises agree. `headless_run` draws forty variants and wants five bodies and thirty different looks.

**The shader samples like a StandardMaterial3D**, with `source_color`, and matches each swap in both colour spaces. What comes back from a `source_color` sampler differs between renderers (the compatibility renderer handed back the stored sRGB values on the dev VM), and the first version converted by hand: every zombie drew a shade from black on a night map while the walls next to it were lit. It answers in the space it matched, so a swapped colour is lit like the rest of the body. Swap colours are given as `vec4` arrays: a `vec3` array is padded on the GPU and a `PackedVector3Array` set into one is read skewed.

**The kit ships three atlases** (`atlas_basic`, `atlas_heavy` for chubby and arm, `atlas_people` for the survivors) that differ in a few swatches. A body drawn with another's atlas wears the wrong colours there, and a palette measured against the wrong one never matches.

## A special is read by its outline

Each special is a different body, or a different shape of one, and stands differently, so a player knows what is coming before they can see its colour:

| Kind | Body | What makes it |
| --- | --- | --- |
| leaper | sam | dark hood and clothes, longer arms, on all fours whenever it is not attacking |
| strangler | basic | 2.05 m, thin, long neck, a long tongue hanging out (the kit's tongue bones, stretched); its pull is a sagging tapered tongue to the victim (`ZzWorldView._present_tongues`) |
| bloater | chubby | wide waist and chest, yellow-green, boils |
| ram | arm | the kit's one-armed brute |
| spitter | lis | long neck, a glowing green throat and mouth that drips |
| rider | basic | 1.2 m, long arms, big head, hunched |
| brute | chubby | 2.95 m, huge arms, small head, bone spikes |
| sleeper | lis | white, long black claws, red eyes |
| screamer | chubby | 2 m, a thin waist and chest, long neck, jaw wide open |
| crawler | basic | no legs; crawls whatever it is doing |
| riot | sam | helmet, visor, a riot shield in front |

Shapes are pose scales on bones, written after the clip every frame (`shape_scales`). **A size is the bone's own, not inherited**: a pose scale carries to every child, so the strangler's long neck would have given it a giant head. Each bone is drawn at its wanted size over its parent's; a name ending `*` sizes a whole limb; a `Vector3` is thicker without longer (Y is along the bone in this kit).

## What a special wears

Hats, shields, boils and the throat are simple meshes on `BoneAttachment3D`s. **An offset is in the body's axes from the bone's joint, at rest** (`_attach` turns it into the bone's frame): the kit's bones point every which way, and an offset in the torso bone's own axes put the riot shield flat under its chin. Each is one more draw call, which is why only specials wear anything.

## How it moves and falls

`CLIPS` maps each `ZzZombieBody.Anim` to a clip and a rate; walking and running are sped to the body's ground speed; a zombie rising or falling fast plays the jump clip (a climb, a drop, a leap). A hit is a flinch over whatever it is doing (the health in the snapshot dropping), so a shotgun's pellets are one flinch and a walking zombie does not stop to play a hit clip. STAGGER plays the hit clip. A swing follows the brain's: the clip restarts with each swing and its strike frame is the damage frame (`SWING_PERIOD`, `HIT_AT`). Against a downed survivor the brain switches to STRIKE_DOWN (reach shortened, damage times `down_attack_damage`; `down_attack` off keeps the standing swing) and the view kneels the body over them. States with no clip are bone poses over a clip: ground strike, a crawler's lunge, the hold (rider's legs wrapped, ram's slam, leaper's claws, strangler's grip), the leap, the crawler's reach and the strangler's reel. `tools/shot.sh --view=strike|strike_down|pin --zombie=<kind>` renders each.

A death is dot-player-char's: the server picks a `DotPlayerDeath` reaction from the killing hit (`ZzHorde.decide_death`: headshot, damage, the weapon's `death_power`, a seed from the zombie and the tick) and sends it last in NPC_GONE, so every screen draws the same fall.

**A killed zombie falls as a skeletal ragdoll** (`ZzWorldView._ragdoll`, into its `ragdolls` yard): dot-player-char copies the view's skeleton as it is posed, with the specials' shapes (the pose scales go with the copy) and what they wear (hats, shields: copied as meshes onto the nearest part), and drops it through the same six parts, joints, pushes, settling and fade every player in the family falls with, the bones riding on the parts (its docs/ragdolls.md, "A skinned body"). One path for a block figure and a skinned one rather than a `PhysicalBoneSimulator3D`, because every reaction tuned on the players (the plank that goes limp when the face lands, the crumple, the launches) then falls the same way here. Bodies lie `sv_ragdoll_time` (`ZzGame.CORPSE_SECONDS`, 6 s, by default) and shrink away. **A dead survivor falls the same way, into the same yard** (`ZzClient._fall` → `ZzWorldView.drop_survivor`, from the figure as drawn, a downed survivor's crawl included): the server picks the fall in `ZzGame.decide_death` (the killing hit's direction, else away from whoever did it; a friend's gun as a weapon def) and it rides DEATH last and optional. One set of `sv_ragdoll*` rules (`ZzGame.ragdoll_rules`, bound REPLICATED by the module and followed through the link) governs both, and the horde draws a zombie's reaction from its weights; a survivor's death evicts the oldest body rather than falling by a clip, because a person has no death clip worth the moment and there is one of them. `sv_ragdoll_style hide` removes a zombie at once. `tools/shot.sh --view=ragdoll --reaction=<id> --seconds=<t>` renders a stand-in killed and its fall.

**Past the cap, the animated fall** (`ZzZombieView.die`): the yard's cap is the machine's (four in a browser tab) and its rules' `max_count`, and a horde dying at once is a few ragdolls and the rest falling by the clip; `sv_ragdoll 0` (`rules.enabled`) is every zombie by the clip. The view turns the body to fall away from the shot and animates the reaction over the kit's death clip: a headshot steps it back, a power launch throws it in an arc, a crumple folds slowly, a face plant is quick and short. Looked at with a frame sequence (common limp, common headshot launch, brute crumple, riot face plant, strangler power launch at 0 to 3.5 s).

## A holder at the lens

The server puts a leaper or a rider on top of its victim, which is right for everybody else and puts its body round the victim's own camera (the play test saw "two black polygons", the inside of its mesh). For the victim alone, the holder's view is taken out from under its body (the camera fade hides whatever hangs off a collider at the lens) and stood a step in front of the camera, facing them (`ZzWorldView._present_lens_holder`). `tools/shot.sh --view=pinned --pin=ride --pin-me` draws it.

## What a horde costs

Measured with `tools/zombie_rack.gd --set=horde --at=5` (sixty commons walking and running at the camera) on the dev VM's software renderer (llvmpipe), which is a worst case and not a browser: one draw call per zombie (61 in the frame), about 140 thousand triangles after LOD, 11 to 13 µs of script per zombie per frame, 27 ms a frame. The Kenney bodies they replaced measured 15 ms and 33 µs on the same scene: the kit's bodies are heavier to rasterise, and cheaper to animate because of the steps below. What keeps it down:

- one surface per body, and one material per look shared by every zombie wearing it;
- the animation advanced every frame within 22 m, every second frame to 45 m, every fourth beyond, with the skipped time (the bones are written only on a frame the clip was evaluated, because the shapes go on top of the clip's pose and would stack);
- `lod_bias` 0.4 on Godot's generated LODs, and nothing drawn past 120 m;
- bodies decimated to 35% at build.

Not measured: a real browser on a real GPU, where the numbers that matter are different. That is in the nightly queue.

## The worker (2026-10-20)

The first body that is ours rather than the kit's: `art-src/zombie_worker.py` takes `zombie_basic.glb`, models a hard hat, hi-vis vest with reflective bands, backpack, tool belt and knee pads, weights each piece whole to one bone, bakes the kit's colours, the gear's paint, dirt and ambient occlusion into one atlas (`atlas_worker.png`) on a fresh UV layout and exports one mesh with the kit's clips. About 9.4k triangles. It is a sixth common variant (`COMMON_BODIES`); `WEARS` is empty because the colours are baked, so the per-zombie skin and clothes swaps do not touch it. The kit body is low-poly with rings of vertices about 0.15 apart at the waist, so the generator fits gear to the skin by `band_fit` over a wide window rather than by exact rings. Render sheets: `reports/models/2026-10-20/`.

## The city zombie (2026-10-26)

A realistic seventh common body, `city`: the CC0 Male City Zombie (OpenGameArt node 111870) on the family's rig. `art-src/zombie_city.py` decimates its 24k polygons to 9k triangles, bakes base colour and a tangent normal map from the full mesh into 1024 px maps (`city_albedo.png`, `city_normal.png`), grades the colour up and toward grey-green (the source is near black under game light), and **moves the rig to the body rather than squeezing the body onto the kit's**: the kit's heads are a third of the body and its legs short, so the zombie_basic skeleton's bones are re-fitted to this body's joints (same names, so its clips play; the clips' translations are scaled with it) and the mesh is weighted from the source's own skin by bone name. Only this body samples a normal map (a second copy of the shader), and `HEAD_TOP` replaces the 1.22 head allowance in `_measure`, so `height` means the real height here. The kit bodies stand about 2.05 m at a `height` of 1.75, so this one reads shorter beside them. The palette swaps do not apply (colour is baked; blood and dirt noise still do). Survivors are dot-player-char's, so a realistic survivor body is that addon's work. Sheets: `reports/models/2026-10-26/`.

## The Sketchfab commons (2026-10-27)

Five more common bodies, `gent`, `cop`, `punk`, `convict` (the four skinned zombies of "Animated Zombie Characters Walking Dead loop" by LasquetiSpice, CC-BY 4.0) and `hazmat` ("Zombie Hazmat" by LxNazarov, CC-BY). `art-src/zombie_sketchfab.py` does what `zombie_city.py` does for any Mixamo-named character: joins its meshes, decimates to 8k triangles, bakes one 1024 colour and one tangent normal map (`<body>_albedo.png`, `<body>_normal.png`), and re-fits the family rig to the character's joints (a finger it lacks is placed from the hand) so the family's clips play; the source loop is dropped. `ZzZombieView.NORMALS` lists the bodies that sample a normal map (they share one shader and, like the city, take no palette swap, blood or dirt splash). The hazmat hood's visor is cut before the bake (a colour bake paints the glass black), so the face shows through a hole. The punk's glasses/hair-card meshes are skipped. Credits: README and the scoreboard header (`ZzZombieView.CREDITS`). Sheets: `reports/models/2026-10-27/`. The shared `make_stores_licence.py` gate lives in zombie-zone-maps and covers its model library, not this game's bodies.

## The Mutant (2026-10-27)

A rare special: a heavy, slow walker with two gravity guns and a jetpack. `npcs/zz_mutant_brain.gd` (the brain), `npcs/zz_mutant_view.gd` (the model, posed by code: it has no clips), `art-src/mutant.py` (the rig and parts from "Buff Mutant 2.0" by Zeldrix, CC-BY). Each gun independently zaps a survivor in range (a beam, damage) or pulls a loose map prop (`ZzHorde.loose_prop_near`), holds it, then throws it. The jetpack (`DotNpcHover` in dot-npc: lift, cruise, hover, land, fuel, cooldown; `DotFxThruster` draws it) carries him over what the navmesh cannot cross. Angry (health under `angry_health`, or a part lost) with a working pack, he charges up in the air, dives at the survivors and slams the ground for area damage. The guns and the pack are limbs with their own hit-zone health (`cfg/addon/dot_npc/limbs.yml`): a gun shot off stops zapping and throwing, a pack shot out drops him and he stays on the ground, both with sparks and smoke. Beams ride the hazard `launched` event (`beam_zap`, `beam_pull`) and the slam rides `exploded` (`slam`), so clients need no new message. Rarity: `zz_mutant_chance` per special roll from wave `zz_mutant_min_wave`. Every number is in `cfg/game/game-zombie-zone/npc/mutant.yml` (live through each kind's `meta`); `zz_mutant_zap_damage`, `zz_mutant_throw_damage`, `zz_mutant_slam_damage`, `zz_mutant_slam_radius`, `zz_mutant_fuel` and `zz_mutant_angry_health` are cvars. Probe: `examples/headless_mutant.gd`. The armour is near black as made; `ZzMutantView` draws the vertex colours unlit by palette swaps.

## The oil monster's model (2026-10-27)

`assets/zombies/zombie_oil_monster.glb` (about 14k triangles in five meshes: `Body`, `Pool`, `Mouth`, `TeethTop`, `TeethBottom`) and `_lod1.glb` (about 3k), built by `art-src/oil_monster.py` from lealeelu's CC-BY fluid-simulation mesh; the data and credit line are `npcs/zz_oil_monster_model.gd`. One skeleton, `root > spine_lo > spine_mid > spine_hi > jaw`, so a pulse is spine scale, a lean is spine rotation, the jaw bone opens the lower lip and bottom teeth, and `root` scale melts the whole body and spreads `Pool` (the `die` clip). Test clips at 30 fps: `idle`, `slide` (both loop), `mouth_open`, `bite`, `grab`, `lift`, `swallow`, `flinch`, `die`; they are rough poses for a view to blend or replace, not final animation. The mouth faces +Z in the file (turn it by PI). The source is a hollow lace of oil over a ball, so the monster reads as a glossy ball on dripping legs over a puddle.

## Marks on the specials' skin

`mark` in a kind's `LOOKS` entry is a bruise or sore colour the palette shader paints where the vertex noise is high in green and low in red (the blood's complement, so the two never overlap). `zz_zombie_detail 0` draws the plain colour. It is one smoothstep pair per fragment and no extra draw call. Contact sheets of the audit (2026-10-25) are under `~/npc-shots/` on the dev VM.

## Dark bodies at night

Lit by a night map's moon alone, the specials' charcoal skins (ram, leaper, brute) drew as black cones with only claws showing, and the spitter's whole-body `glow` drew it as a flat green silhouette. The shader now emits `BODY_LIFT` of the body's own colour, and a kind's `glow` reaches the body at `GLOW_BODY` (the throat is its own mesh). `zombie_rack.gd --night` renders the sheet by a night's light; `--set=ragdolls [--sever=head,legL] [--kinds=...]` drops each kind as the world view does.

A special that drew as a legless, headless cone was a zombie whose limbs had come off, not a model fault: a limb's health is a share of the kind's base health, so a later wave's scaled health, and Instakill's boosted damage, stripped them in a hit. `ZzHorde.limb_damage` now scales a hit by base over real health and skips Instakill's boost; `zz_limb_follow_health 0` restores the old rule.
