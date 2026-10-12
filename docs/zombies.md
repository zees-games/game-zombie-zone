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

`CLIPS` maps each `ZzZombieBody.Anim` to a clip and a rate; walking and running are sped to the body's ground speed; a zombie rising or falling fast plays the jump clip (a climb, a drop, a leap). A hit is a flinch over whatever it is doing (the health in the snapshot dropping), so a shotgun's pellets are one flinch and a walking zombie does not stop to play a hit clip. STAGGER plays the hit clip.

A death is dot-player-char's: the server picks a `DotPlayerDeath` reaction from the killing hit (`ZzHorde.decide_death`: headshot, damage, the weapon's `death_power`, a seed from the zombie and the tick) and sends it last in NPC_GONE, so every screen draws the same fall.

**A killed zombie falls as a skeletal ragdoll** (`ZzWorldView._ragdoll`, into its `ragdolls` yard): dot-player-char copies the view's skeleton as it is posed, with the specials' shapes (the pose scales go with the copy) and what they wear (hats, shields: copied as meshes onto the nearest part), and drops it through the same six parts, joints, pushes, settling and fade every player in the family falls with, the bones riding on the parts (its docs/ragdolls.md, "A skinned body"). One path for a block figure and a skinned one rather than a `PhysicalBoneSimulator3D`, because every reaction tuned on the players (the plank that goes limp when the face lands, the crumple, the launches) then falls the same way here. Bodies lie `CORPSE_SECONDS` and shrink away.

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
